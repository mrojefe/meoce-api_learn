-- Audit de conformité 2026-07-25 — passage d'un journal « valeurs » à un
-- journal EXPLOITABLE en cas de litige ou de contrôle.
--
-- Constat de l'audit :
--   • `changed_by` NULL sur 28 991 lignes (100 %) → aucune imputabilité.
--   • Aucun contexte (IP, user-agent, requête) → impossible de distinguer
--     l'utilisateur, l'admin ou un worker Airflow.
--   • audit_logs modifiable par `authenticated` (UPDATE/DELETE accordés) →
--     une trace altérable ne prouve rien.
--   • Aucun événement d'authentification (connexion, échec, reset) tracé.
--   • Couverture à l'envers : 85 % du volume = news_articles (données
--     publiques scrapées), tandis que portfolio_transactions, positions,
--     payment_events et user_features n'étaient pas tracés du tout.
--
-- Rétention : 3 ANS MINIMUM (décision JF 2026-07-25). Projection ~2 Go sur
-- 3 ans pour 319 Go libres — on conserve tout, y compris news_articles.

-- ── 1. Contexte de la requête (qui, d'où) ─────────────────────────────────
-- PostgREST expose les en-têtes HTTP via current_setting('request.headers').
-- L'API MEOCE utilise un JWT MAISON (pas Supabase Auth) et appelle PostgREST
-- avec la clé service_role : `request.jwt.claims` ne contient donc QUE le rôle
-- technique, jamais l'utilisateur final. D'où le passage explicite de l'acteur
-- par l'en-tête `X-Actor-Id`, posé par l'API (app/core/database.py).
--
-- Ordre de résolution :
--   1. app.actor_id          — SET LOCAL, pour psql / workers Airflow
--   2. en-tête X-Actor-Id    — appels API via PostgREST
--   3. NULL                  — action système non attribuable (scrapers)
CREATE OR REPLACE FUNCTION public.audit_request_context()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $function$
DECLARE
  headers jsonb;
  actor   text;
BEGIN
  BEGIN
    headers := nullif(pg_catalog.current_setting('request.headers', true), '')::jsonb;
  EXCEPTION WHEN others THEN
    headers := NULL;
  END;

  actor := nullif(pg_catalog.current_setting('app.actor_id', true), '');
  IF actor IS NULL AND headers IS NOT NULL THEN
    actor := headers ->> 'x-actor-id';
  END IF;

  RETURN jsonb_build_object(
    'actor_id',   nullif(actor, ''),
    'actor_role', pg_catalog.current_setting('role', true),
    -- x-real-ip est posé par Kong ; x-forwarded-for peut contenir une chaîne
    -- d'IP (client, proxies) → on garde le 1er élément, le client réel.
    -- NB : NULLIF/COALESCE/CASE sont des constructions SQL, PAS des fonctions —
    -- elles ne se qualifient pas par schéma (pg_catalog.nullif n'existe pas) et
    -- restent résolues malgré `SET search_path TO ''`.
    'client_ip',  coalesce(
                    headers ->> 'x-real-ip',
                    nullif(pg_catalog.split_part(coalesce(headers ->> 'x-forwarded-for', ''), ',', 1), '')),
    'user_agent', pg_catalog.left(coalesce(headers ->> 'user-agent', ''), 300),
    'request_id', headers ->> 'x-kong-request-id',
    'source',     CASE
                    WHEN headers IS NULL THEN 'db_direct'   -- psql, migration, worker
                    ELSE 'api'
                  END
  );
END;
$function$;

COMMENT ON FUNCTION public.audit_request_context() IS
  'Contexte (acteur, IP, user-agent) d''une écriture, pour audit_logs et auth_events. Voir migration 20260725010000.';

-- ── 2. Enrichissement de audit_logs ───────────────────────────────────────
ALTER TABLE public.audit_logs
  ADD COLUMN IF NOT EXISTS actor_id   uuid,
  ADD COLUMN IF NOT EXISTS actor_role text,
  ADD COLUMN IF NOT EXISTS client_ip  inet,
  ADD COLUMN IF NOT EXISTS user_agent text,
  ADD COLUMN IF NOT EXISTS request_id text,
  ADD COLUMN IF NOT EXISTS source     text;

COMMENT ON COLUMN public.audit_logs.changed_by IS
  'OBSOLÈTE — jamais renseignée (100 % NULL avant 2026-07-25). Utiliser actor_id.';
COMMENT ON COLUMN public.audit_logs.actor_id IS
  'Utilisateur à l''origine de l''action. NULL = action système (scraper, migration).';
COMMENT ON COLUMN public.audit_logs.source IS
  'api = via PostgREST ; db_direct = psql/worker/migration.';

CREATE INDEX IF NOT EXISTS idx_audit_logs_actor      ON public.audit_logs(actor_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_changed_at ON public.audit_logs(changed_at DESC);

-- ── 3. Trigger d'audit enrichi ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.process_audit_log()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  ctx     jsonb := public.audit_request_context();
  v_actor uuid;
  v_ip    inet;
BEGIN
  -- Un en-tête falsifié ne doit pas casser l'écriture métier : conversions
  -- défensives, on préfère une trace sans acteur à un INSERT qui échoue.
  BEGIN v_actor := (ctx ->> 'actor_id')::uuid;  EXCEPTION WHEN others THEN v_actor := NULL; END;
  BEGIN v_ip    := (ctx ->> 'client_ip')::inet; EXCEPTION WHEN others THEN v_ip    := NULL; END;

  IF (TG_OP = 'UPDATE') THEN
    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data,
                                   actor_id, actor_role, client_ip, user_agent, request_id, source)
    VALUES (TG_TABLE_NAME, OLD.id::text, 'UPDATE',
            public.redact_audit_payload(pg_catalog.to_jsonb(OLD)),
            public.redact_audit_payload(pg_catalog.to_jsonb(NEW)),
            v_actor, ctx->>'actor_role', v_ip, ctx->>'user_agent', ctx->>'request_id', ctx->>'source');
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    INSERT INTO public.audit_logs (table_name, record_id, action, old_data,
                                   actor_id, actor_role, client_ip, user_agent, request_id, source)
    VALUES (TG_TABLE_NAME, OLD.id::text, 'DELETE',
            public.redact_audit_payload(pg_catalog.to_jsonb(OLD)),
            v_actor, ctx->>'actor_role', v_ip, ctx->>'user_agent', ctx->>'request_id', ctx->>'source');
    RETURN OLD;

  ELSIF (TG_OP = 'INSERT') THEN
    INSERT INTO public.audit_logs (table_name, record_id, action, new_data,
                                   actor_id, actor_role, client_ip, user_agent, request_id, source)
    VALUES (TG_TABLE_NAME, NEW.id::text, 'INSERT',
            public.redact_audit_payload(pg_catalog.to_jsonb(NEW)),
            v_actor, ctx->>'actor_role', v_ip, ctx->>'user_agent', ctx->>'request_id', ctx->>'source');
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$function$;

-- ── 4. Inviolabilité ──────────────────────────────────────────────────────
-- Une trace modifiable ne prouve rien. On bloque UPDATE/DELETE, sauf pour la
-- purge de rétention qui doit lever explicitement un drapeau de session.
CREATE OR REPLACE FUNCTION public.audit_logs_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  IF pg_catalog.current_setting('app.allow_audit_maintenance', true) = 'on' THEN
    RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
  END IF;
  RAISE EXCEPTION
    'audit_logs est append-only : % interdit. Purge de rétention : SET LOCAL app.allow_audit_maintenance = ''on'';', TG_OP
    USING ERRCODE = 'insufficient_privilege';
END;
$function$;

DROP TRIGGER IF EXISTS trg_audit_logs_immutable ON public.audit_logs;
CREATE TRIGGER trg_audit_logs_immutable
BEFORE UPDATE OR DELETE ON public.audit_logs
FOR EACH ROW EXECUTE FUNCTION public.audit_logs_immutable();

REVOKE UPDATE, DELETE, TRUNCATE ON public.audit_logs FROM anon, authenticated;

-- ── 5. Événements d'authentification ──────────────────────────────────────
-- Aucune table ne traçait les connexions : impossible de détecter une attaque
-- par force brute ou de répondre à « qui s'est connecté, quand, d'où ».
CREATE TABLE IF NOT EXISTS public.auth_events (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type   text NOT NULL CHECK (event_type IN (
                 'login_success','login_failed','logout',
                 'signup','password_reset_requested','password_reset_completed',
                 'email_verified','otp_sent','otp_failed','otp_verified',
                 'token_revoked','account_locked')),
  user_id      uuid REFERENCES public.users(id) ON DELETE SET NULL,
  -- Conservé même si le compte est supprimé (RGPD : la traçabilité sécurité
  -- prime) et rempli sur échec, quand aucun user_id n'est connu.
  identifier   text,
  success      boolean NOT NULL DEFAULT true,
  reason       text,
  client_ip    inet,
  user_agent   text,
  request_id   text,
  metadata     jsonb,
  created_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.auth_events IS
  'Journal des événements d''authentification. Append-only, rétention 3 ans. Migration 20260725010000.';
COMMENT ON COLUMN public.auth_events.identifier IS
  'Email/téléphone utilisé lors de la tentative — indispensable pour tracer les échecs (aucun user_id alors).';

CREATE INDEX IF NOT EXISTS idx_auth_events_user    ON public.auth_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_events_type    ON public.auth_events(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_events_ip      ON public.auth_events(client_ip, created_at DESC);
-- Détection de force brute : échecs récents par identifiant.
CREATE INDEX IF NOT EXISTS idx_auth_events_failed  ON public.auth_events(identifier, created_at DESC)
  WHERE success = false;

ALTER TABLE public.auth_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS auth_events_no_public_access ON public.auth_events;
CREATE POLICY auth_events_no_public_access ON public.auth_events FOR ALL USING (false);
REVOKE ALL ON public.auth_events FROM anon, authenticated;

DROP TRIGGER IF EXISTS trg_auth_events_immutable ON public.auth_events;
CREATE TRIGGER trg_auth_events_immutable
BEFORE UPDATE OR DELETE ON public.auth_events
FOR EACH ROW EXECUTE FUNCTION public.audit_logs_immutable();

-- Helper appelé par l'API (RPC) — remplit seul le contexte réseau.
CREATE OR REPLACE FUNCTION public.log_auth_event(
  p_event_type text,
  p_user_id    uuid    DEFAULT NULL,
  p_identifier text    DEFAULT NULL,
  p_success    boolean DEFAULT true,
  p_reason     text    DEFAULT NULL,
  p_metadata   jsonb   DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  ctx  jsonb := public.audit_request_context();
  v_ip inet;
  v_id uuid;
BEGIN
  BEGIN v_ip := (ctx ->> 'client_ip')::inet; EXCEPTION WHEN others THEN v_ip := NULL; END;

  INSERT INTO public.auth_events (event_type, user_id, identifier, success, reason,
                                  client_ip, user_agent, request_id, metadata)
  VALUES (p_event_type, p_user_id, p_identifier, p_success, p_reason,
          v_ip, ctx->>'user_agent', ctx->>'request_id', p_metadata)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.log_auth_event(text, uuid, text, boolean, text, jsonb) FROM PUBLIC, anon, authenticated;

-- ── 6. Couverture : ajout des tables critiques non tracées ────────────────
-- news_articles reste audité (décision JF : « on garde tout »), même si c'est
-- 85 % du volume — l'espace disque n'est pas contraint (319 Go libres).
DO $do$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'portfolio_transactions',  -- mouvements d'argent
    'positions',               -- avoirs
    'payment_events',          -- cycle de vie des paiements
    'user_features',           -- attribution de droits (élévation de privilèges)
    'subscription_plans',      -- tarification
    'platform_config',         -- configuration globale
    'user_alerts',
    'watchlist_items'
  ] LOOP
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'public' AND c.relname = t AND c.relkind = 'r')
    THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_%1$s ON public.%1$I', t);
      EXECUTE format(
        'CREATE TRIGGER trg_audit_%1$s AFTER INSERT OR UPDATE OR DELETE ON public.%1$I
         FOR EACH ROW EXECUTE FUNCTION public.process_audit_log()', t);
    END IF;
  END LOOP;
END
$do$;

-- ── 7. Rétention 3 ans ────────────────────────────────────────────────────
-- Rien n'est supprimé avant 3 ans révolus. Fonction manuelle : pg_cron n'est
-- pas installé sur cette instance (vérifié 2026-07-25) — à planifier via un
-- DAG Airflow ou un cron système le jour où le volume le justifiera.
CREATE OR REPLACE FUNCTION public.purge_audit_beyond_retention(p_years int DEFAULT 3)
RETURNS TABLE(purged_audit bigint, purged_auth bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  cutoff timestamptz := now() - make_interval(years => p_years);
  a bigint; b bigint;
BEGIN
  IF p_years < 3 THEN
    RAISE EXCEPTION 'Rétention minimale de 3 ans (demandé : % an(s)).', p_years;
  END IF;
  -- Lève le verrou d'inviolabilité pour cette transaction uniquement.
  PERFORM pg_catalog.set_config('app.allow_audit_maintenance', 'on', true);

  DELETE FROM public.audit_logs  WHERE changed_at < cutoff;  GET DIAGNOSTICS a = ROW_COUNT;
  DELETE FROM public.auth_events WHERE created_at < cutoff;  GET DIAGNOSTICS b = ROW_COUNT;

  RETURN QUERY SELECT a, b;
END;
$function$;

COMMENT ON FUNCTION public.purge_audit_beyond_retention(int) IS
  'Purge au-delà de la rétention (3 ans minimum, refuse en deçà). Non planifiée : pg_cron absent.';

REVOKE ALL ON FUNCTION public.purge_audit_beyond_retention(int) FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- CORRECTIF URGENT — process_audit_log() cassait toute écriture sur les tables
-- auditées SANS colonne `id`
--
-- La refonte « audit forensics » (20260725010000) lit `OLD.id::text` /
-- `NEW.id::text` en dur. Or 5 tables auditées n'ont PAS de colonne `id`
-- (clé primaire différente) : platform_config, positions, subscription_plans,
-- user_features, watchlist_items.
-- Sur chacune, TOUT INSERT/UPDATE/DELETE plantait avec
-- « record "old" has no field "id" » — dont les portefeuilles (positions) et
-- les listes de suivi (watchlist_items), très actifs en production.
-- Constaté en réel : impossible de mettre à jour subscription_plans.
--
-- Correctif minimal, sans changer la sémantique de la refonte forensics :
-- l'identifiant d'enregistrement est extrait de la ligne JSON de façon
-- NULL-SAFE (jsonb ->> renvoie NULL au lieu de planter), en essayant les clés
-- primaires connues du schéma. `record_id` étant NOT NULL, repli sur 'n/a' —
-- acceptable : la ligne COMPLÈTE est de toute façon dans old_data/new_data.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.audit_record_id(j jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    j ->> 'id',        -- PK standard (majorité des tables)
    j ->> 'code',      -- subscription_plans
    j ->> 'key',       -- platform_config, features
    j ->> 'user_id',   -- positions, user_features, watchlist_items (1re colonne de PK composite)
    'n/a'
  );
$$;

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
    VALUES (TG_TABLE_NAME, public.audit_record_id(pg_catalog.to_jsonb(OLD)), 'UPDATE',
            public.redact_audit_payload(pg_catalog.to_jsonb(OLD)),
            public.redact_audit_payload(pg_catalog.to_jsonb(NEW)),
            v_actor, ctx->>'actor_role', v_ip, ctx->>'user_agent', ctx->>'request_id', ctx->>'source');
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    INSERT INTO public.audit_logs (table_name, record_id, action, old_data,
                                   actor_id, actor_role, client_ip, user_agent, request_id, source)
    VALUES (TG_TABLE_NAME, public.audit_record_id(pg_catalog.to_jsonb(OLD)), 'DELETE',
            public.redact_audit_payload(pg_catalog.to_jsonb(OLD)),
            v_actor, ctx->>'actor_role', v_ip, ctx->>'user_agent', ctx->>'request_id', ctx->>'source');
    RETURN OLD;

  ELSIF (TG_OP = 'INSERT') THEN
    INSERT INTO public.audit_logs (table_name, record_id, action, new_data,
                                   actor_id, actor_role, client_ip, user_agent, request_id, source)
    VALUES (TG_TABLE_NAME, public.audit_record_id(pg_catalog.to_jsonb(NEW)), 'INSERT',
            public.redact_audit_payload(pg_catalog.to_jsonb(NEW)),
            v_actor, ctx->>'actor_role', v_ip, ctx->>'user_agent', ctx->>'request_id', ctx->>'source');
    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$function$;

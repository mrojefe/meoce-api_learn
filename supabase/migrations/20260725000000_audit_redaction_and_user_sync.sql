-- Audit sécurité 2026-07-25 — deux correctifs sur le cycle de vie utilisateur.
--
-- 1) FUITE DE SECRETS DANS L'AUDIT
--    process_audit_log() copiait la ligne ENTIÈRE en JSON (to_jsonb(OLD/NEW)),
--    donc `user_profiles.password_hash` se retrouvait dupliqué en clair-hash
--    dans audit_logs : 420 lignes couvrant 180 utilisateurs distincts. RLS
--    bloque l'accès public à audit_logs, mais toute sauvegarde volée ou tout
--    accès service_role doublait la surface d'exposition des identifiants.
--    → on masque les colonnes sensibles AVANT insertion, et on purge l'existant.
--
-- 2) DÉSYNCHRONISATION users ↔ user_profiles
--    mirror_user_profile() ne se déclenchait qu'AFTER INSERT. Or /api/user/profile
--    (PUT) écrit email/first_name/last_name dans user_profiles UNIQUEMENT → la
--    table `users`, qui sert l'affichage PUBLIC (auteur des commentaires news
--    dans news.py, classement portefeuille dans portfolios.py), gardait des
--    valeurs périmées indéfiniment. Constaté en prod : 4 comptes avec un prénom
--    renseigné côté profil mais vide côté `users`.
--    → miroir étendu à UPDATE + rattrapage des lignes déjà divergentes.

-- ── 1. Masquage des colonnes sensibles dans l'audit ────────────────────────
-- Liste volontairement explicite (pas de détection par motif) : une colonne
-- sensible ajoutée plus tard DOIT être ajoutée ici sciemment.
CREATE OR REPLACE FUNCTION public.redact_audit_payload(payload jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN payload IS NULL THEN NULL
    ELSE payload
         - 'password_hash'
         - 'refresh_token'
         - 'access_token'
         - 'otp_code'
         - 'reset_token'
  END;
$function$;

COMMENT ON FUNCTION public.redact_audit_payload(jsonb) IS
  'Retire les colonnes sensibles d''un payload d''audit. Utilisé par process_audit_log() — voir migration 20260725000000.';

CREATE OR REPLACE FUNCTION public.process_audit_log()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  -- Les payloads passent par redact_audit_payload() : jamais de secret en clair
  -- dans audit_logs (cf. migration 20260725000000).
  IF (TG_OP = 'UPDATE') THEN
    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data)
    VALUES (TG_TABLE_NAME, OLD.id::text, 'UPDATE',
            public.redact_audit_payload(pg_catalog.to_jsonb(OLD)),
            public.redact_audit_payload(pg_catalog.to_jsonb(NEW)));
    RETURN NEW;
  ELSIF (TG_OP = 'DELETE') THEN
    INSERT INTO public.audit_logs (table_name, record_id, action, old_data)
    VALUES (TG_TABLE_NAME, OLD.id::text, 'DELETE',
            public.redact_audit_payload(pg_catalog.to_jsonb(OLD)));
    RETURN OLD;
  ELSIF (TG_OP = 'INSERT') THEN
    INSERT INTO public.audit_logs (table_name, record_id, action, new_data)
    VALUES (TG_TABLE_NAME, NEW.id::text, 'INSERT',
            public.redact_audit_payload(pg_catalog.to_jsonb(NEW)));
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$function$;

-- Purge de l'historique déjà écrit (on ne supprime pas les lignes d'audit —
-- leur valeur de traçabilité reste — on en retire seulement les secrets).
UPDATE public.audit_logs
SET old_data = public.redact_audit_payload(old_data),
    new_data = public.redact_audit_payload(new_data)
WHERE old_data ? 'password_hash'
   OR new_data ? 'password_hash'
   OR old_data ? 'refresh_token'
   OR new_data ? 'refresh_token';

-- ── 2. Miroir user_profiles → users, à l'INSERT ET à l'UPDATE ─────────────
CREATE OR REPLACE FUNCTION public.mirror_user_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    INSERT INTO public.users (id, email, phone, username, first_name, last_name)
    VALUES (
      NEW.id,
      NEW.email,
      NEW.phone,
      CASE
        WHEN NEW.email IS NOT NULL
        THEN pg_catalog.split_part(NEW.email, '@', 1) || '_' || pg_catalog.left(NEW.id::text, 4)
        ELSE 'user_' || pg_catalog.left(NEW.id::text, 8)
      END,
      NEW.first_name,
      NEW.last_name
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
  END IF;

  -- UPDATE : on répercute uniquement les champs miroir. `username` n'est PAS
  -- touché — il vit sur `users` et se modifie via /api/user/profile, il ne doit
  -- jamais être écrasé par une valeur dérivée de l'email.
  UPDATE public.users
  SET email      = NEW.email,
      phone      = NEW.phone,
      first_name = NEW.first_name,
      last_name  = NEW.last_name,
      updated_at = pg_catalog.now()
  WHERE id = NEW.id
    AND (email      IS DISTINCT FROM NEW.email
      OR phone      IS DISTINCT FROM NEW.phone
      OR first_name IS DISTINCT FROM NEW.first_name
      OR last_name  IS DISTINCT FROM NEW.last_name);

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_mirror_user_profile ON public.user_profiles;
CREATE TRIGGER trg_mirror_user_profile
AFTER INSERT OR UPDATE ON public.user_profiles
FOR EACH ROW EXECUTE FUNCTION public.mirror_user_profile();

-- Rattrapage des lignes déjà divergentes (constaté : 4 prénoms / 3 noms).
UPDATE public.users u
SET email      = p.email,
    phone      = p.phone,
    first_name = p.first_name,
    last_name  = p.last_name,
    updated_at = now()
FROM public.user_profiles p
WHERE p.id = u.id
  AND (u.email      IS DISTINCT FROM p.email
    OR u.phone      IS DISTINCT FROM p.phone
    OR u.first_name IS DISTINCT FROM p.first_name
    OR u.last_name  IS DISTINCT FROM p.last_name);

-- ============================================================
-- Fix a table-naming inversion: `user_profiles` currently holds
-- identity/credentials (email, password_hash, phone, auth_provider —
-- created by 20260611161640_create_user_profiles_auth.sql), and `users`
-- currently holds display data (first_name, last_name, avatar_url,
-- username, bio). That is backwards from convention and from the app's
-- own intent (`users` = the core account/auth row, `user_profiles` =
-- extended display/profile data). This migration swaps the two names,
-- and follows up by relocating `country`/`profile_completed` — added by
-- 20260616175948_add_profile_and_preferences_columns.sql onto the
-- *identity* table — onto the renamed *display* table, since both are
-- display/onboarding facts, not credentials.
--
-- Append-only convention: this is a new migration, not an edit of the
-- two migrations above.
-- ============================================================

-- --------------------------------------------------------------
-- 1. Swap the table names.
--
-- Postgres has no atomic "swap two names" — renaming straight across
-- would collide on the second statement (the target name is still taken
-- by the other table until its own rename runs). Go through a scratch
-- name instead: old user_profiles (identity) -> users_tmp_swap,
-- old users (display) -> user_profiles, users_tmp_swap -> users.
-- Grants, RLS, indexes, and triggers all move with the table — a rename
-- only changes the name of the existing relation, not its OID or any
-- privilege attached to it.
-- --------------------------------------------------------------

ALTER TABLE public.user_profiles RENAME TO users_tmp_swap;
ALTER TABLE public.users RENAME TO user_profiles;
ALTER TABLE public.users_tmp_swap RENAME TO users;

-- --------------------------------------------------------------
-- 2. Move `country`/`profile_completed` from the credentials table
--    (now `users`, after the rename above) onto the display table
--    (now `user_profiles`).
--
-- These columns are recent (20260616175948) and, in staging today, are
-- default/empty for every row — but this still copies data across
-- properly via UPDATE ... FROM, rather than drop-and-recreate blindly,
-- in case any real values exist by the time this runs elsewhere.
-- --------------------------------------------------------------

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS country           TEXT,
  ADD COLUMN IF NOT EXISTS profile_completed BOOLEAN NOT NULL DEFAULT false;

UPDATE public.user_profiles AS p
   SET country           = u.country,
       profile_completed = u.profile_completed
  FROM public.users AS u
 WHERE u.id = p.id;

ALTER TABLE public.users
  DROP COLUMN IF EXISTS country,
  DROP COLUMN IF EXISTS profile_completed;

-- --------------------------------------------------------------
-- 3. Rewrite mirror_user_profile() for the new names.
--
-- Original body (see 20260904193000_fix_mirror_trigger_after_split.sql):
-- fires AFTER INSERT on the credentials table (was `user_profiles`, now
-- `users`) and creates the matching display row (was `users`, now
-- `user_profiles`), deriving a default username from the email. The
-- trigger's firing table is the same physical relation as before (the
-- rename carried the trigger along with it, still attached to what is
-- now named `users`) — it is dropped and recreated here only so its
-- definition is explicit and versioned in this migration rather than
-- left as an implicit side effect of the rename. The function body's
-- own INSERT target flips from `users` to `user_profiles`, since that's
-- the table that now holds the display row this trigger creates.
-- --------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_mirror_user_profile ON public.users;

CREATE OR REPLACE FUNCTION public.mirror_user_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    INSERT INTO public.user_profiles (id, username)
    VALUES (
      NEW.id,
      CASE
        WHEN NEW.email IS NOT NULL
        THEN pg_catalog.split_part(NEW.email, '@', 1) || '_' || pg_catalog.left(NEW.id::text, 4)
        ELSE 'user_' || pg_catalog.left(NEW.id::text, 8)
      END
    )
    ON CONFLICT (id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.mirror_user_profile() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_mirror_user_profile
  AFTER INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.mirror_user_profile();

-- --------------------------------------------------------------
-- 4. RLS / grants.
--
-- The service_role-only posture (RLS enabled, no policy, no grant to
-- anon/authenticated) was defined on the physical relation created by
-- 20260611161640_create_user_profiles_auth.sql for holding credentials.
-- A rename does not touch grants or RLS state — that relation is now
-- named `users` and is still exactly as locked down. Restated explicitly
-- here so this posture is not lost sight of at the new name, and so a
-- future reader of `\d+ users` sees why.
-- --------------------------------------------------------------

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.users FROM anon, authenticated;

COMMENT ON TABLE public.users IS
  'Identity/credentials: email, password_hash, phone, auth_provider. '
  'RLS enabled, no policy, no grant to anon/authenticated — service_role '
  '(meoce-api) only, never exposed directly to a client.';

COMMENT ON TABLE public.user_profiles IS
  'App-facing display/profile data: username, first_name, last_name, '
  'display_name, bio, avatar_url, country, profile_completed. Row '
  'created by trg_mirror_user_profile on signup.';

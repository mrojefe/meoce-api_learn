-- Fix mirror_user_profile() after the users/user_profiles split (see
-- 20260904190000_split_users_profiles.sql).
--
-- This trigger's job was keeping the duplicated email/phone/first_name/
-- last_name columns in sync. That duplication is gone now — email/phone live
-- only on user_profiles, first_name/last_name only on users — so the UPDATE
-- case has nothing left to mirror. Broke live: UPDATE user_profiles.phone
-- referenced users.email, which no longer exists.
--
-- INSERT still needs to create the users row on signup (username is derived
-- here, from the email that only exists on user_profiles at that point), but
-- without the dropped email/phone columns. first_name/last_name no longer
-- exist on user_profiles at all (moved to users only) — nothing to carry
-- over; they get set later via PATCH /users/me.

CREATE OR REPLACE FUNCTION public.mirror_user_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    INSERT INTO public.users (id, username)
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

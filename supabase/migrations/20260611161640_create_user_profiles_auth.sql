-- ============================================================
-- AUTH CUSTOM : table user_profiles manquante + chaînage users
--
-- Contexte : l'app utilise une auth maison (bcrypt + JWT custom,
-- cf meoce-frontend src/lib/auth.ts et /api/auth/*) qui lit/écrit
-- `user_profiles`. Cette table existe dans l'ANCIEN projet Supabase
-- (Afriview_old, 12 comptes) mais n'a jamais été créée ici → signup
-- et login sont cassés sur la base canonique (users_count = 0).
--
-- Schéma repris à l'identique de l'ancien projet (vérifié le
-- 2026-06-11 via information_schema), avec en plus :
-- 1. RLS stricte : service_role uniquement (password_hash dedans,
--    JAMAIS de grant anon/authenticated).
-- 2. users (profil public, cible des FK portfolios/watchlists/...)
--    perd sa FK vers auth.users : l'auth custom ne peuple pas
--    auth.users. Un trigger miroir crée la ligne users à chaque
--    signup, avec un username par défaut dérivé de l'email
--    (affiché au leaderboard des portefeuilles publics).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_profiles (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name      TEXT,
  phone          TEXT        UNIQUE,
  timezone       TEXT        DEFAULT 'Africa/Abidjan',
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now(),
  email          TEXT        UNIQUE,
  password_hash  TEXT,
  auth_provider  TEXT        DEFAULT 'password',
  phone_verified BOOLEAN     DEFAULT false,
  first_name     TEXT,
  last_name      TEXT,
  CHECK (email IS NOT NULL OR phone IS NOT NULL)
);

-- RLS activée, AUCUNE policy ni grant : seule la service_role
-- (routes serveur Next + meoce-api) peut y accéder.
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_profiles FROM anon, authenticated;

CREATE TRIGGER trg_user_profiles_updated_at
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- users ne dépend plus de auth.users (auth custom)
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_id_fkey;

-- Miroir signup → profil public users (cible des FK portfolios etc.)
CREATE OR REPLACE FUNCTION public.mirror_user_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.users (id, email, phone, username, first_name, last_name)
  VALUES (
    NEW.id,
    NEW.email,
    NEW.phone,
    CASE
      WHEN NEW.email IS NOT NULL
      THEN split_part(NEW.email, '@', 1) || '_' || left(NEW.id::text, 4)
      ELSE 'user_' || left(NEW.id::text, 8)
    END,
    NEW.first_name,
    NEW.last_name
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mirror_user_profile() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_mirror_user_profile
  AFTER INSERT ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.mirror_user_profile();

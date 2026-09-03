ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS country          TEXT,
  ADD COLUMN IF NOT EXISTS profile_completed BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.user_preferences
  ADD COLUMN IF NOT EXISTS investor_experience TEXT,
  ADD COLUMN IF NOT EXISTS investor_horizon    TEXT,
  ADD COLUMN IF NOT EXISTS investor_sectors    TEXT[],
  ADD COLUMN IF NOT EXISTS discovery_source    TEXT,
  ADD COLUMN IF NOT EXISTS notif_pref          TEXT;

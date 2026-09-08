-- Clean split: user_profiles = auth/credentials, users = app display profile.
--
-- Today 8 columns are duplicated across both tables (email, phone, first_name,
-- last_name, avatar_url, + timestamps/id), with nothing enforcing they stay in
-- sync. Verified 0 mismatches in staging right now, but that's luck, not a
-- constraint. Each fact gets exactly one home:
--   - user_profiles: identity/credentials (email, phone, password_hash,
--     auth_provider, email_verified, phone_verified)
--   - users: app-facing display data (first_name, last_name, avatar_url, ...)
-- full_name dropped entirely — derivable from first_name + last_name.

-- Backfill users' first_name/last_name/avatar_url from user_profiles first,
-- in case any of the 2 extra user_profiles-less users differ.
UPDATE users u
   SET first_name = COALESCE(u.first_name, p.first_name),
       last_name  = COALESCE(u.last_name, p.last_name),
       avatar_url = COALESCE(u.avatar_url, p.avatar_url)
  FROM user_profiles p
 WHERE p.id = u.id;

ALTER TABLE user_profiles DROP COLUMN first_name;
ALTER TABLE user_profiles DROP COLUMN last_name;
ALTER TABLE user_profiles DROP COLUMN full_name;
ALTER TABLE user_profiles DROP COLUMN avatar_url;

ALTER TABLE users DROP COLUMN email;
ALTER TABLE users DROP COLUMN phone;

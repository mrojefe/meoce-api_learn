-- Temporary: mark real (non-seed) accounts as email_verified so the new
-- login gate (verify_password_match requires email_verified=true) doesn't
-- lock out existing users who never went through a real verification flow.
--
-- TODO: build the actual email verification flow (send link, confirm token,
-- flip this column for real) before this stops being a workaround.

UPDATE user_profiles p
   SET email_verified = true
  FROM users u
 WHERE u.id = p.id
   AND u.account_kind <> 'seed';

-- ============================================================
-- Adds the two columns google_sign_in needs to anchor a Google account
-- on something that never changes.
--
-- Google's own `email`, `given_name`, `family_name`, `picture`, `locale`,
-- and `hd` claims can all change over time (a person can change their
-- Google account email, rename themselves, swap their photo, change
-- their Workspace domain). The `sub` claim is the one Google guarantees
-- is stable for the lifetime of the account, so it — not email — is the
-- right thing to match an existing account by on a returning sign-in.
--
-- Both columns are nullable: not every `users` row is Google-linked (a
-- password or WhatsApp account has neither), so NOT NULL would break
-- every non-Google signup path.
--
-- `google_sub` carries a UNIQUE constraint: two different `users` rows
-- must never claim the same Google identity — that would mean two
-- accounts both believe they are "the" account for one real person's
-- Google sign-in, which the lookup-by-sub logic in google_auth.py
-- assumes can never happen (it expects at most one match).
--
-- `google_hd` (Google's "hosted domain" claim, e.g. a company's Workspace
-- domain) has no uniqueness requirement — many accounts can share the
-- same Workspace domain, it's descriptive metadata only.
-- ============================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS google_sub TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS google_hd  TEXT;

COMMENT ON COLUMN public.users.google_sub IS
  'Google''s stable per-account identifier (the ID token''s `sub` claim). '
  'Written once at Google-linking time and never overwritten afterward — '
  'it is the anchor a later sign-in is matched by, not a field Google '
  'refreshes. NULL for accounts never linked to Google. UNIQUE: two '
  'different users rows must never claim the same Google identity.';

COMMENT ON COLUMN public.users.google_hd IS
  'Google''s "hosted domain" claim (e.g. a Workspace domain), refreshed '
  'from the token on every Google sign-in like the rest of Google''s '
  'own fields. NULL for accounts never linked to Google, or for a '
  'personal (non-Workspace) Google account.';

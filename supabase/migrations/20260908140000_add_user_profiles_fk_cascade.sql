-- `user_profiles.id` has always been a 1:1 companion to `users.id` (every
-- row created by `mirror_user_profile()`'s trigger on a `users` INSERT),
-- but nothing ever enforced that relationship at the database level — no
-- foreign key existed at all. Deleting a `users` row (routine in test
-- cleanup, and in real account deletion eventually) left its
-- `user_profiles` row behind forever, with nothing to catch or clean it
-- up. Found in staging on 2026-09-08: 429 orphaned `user_profiles` rows
-- had accumulated with no matching `users` row, out of 595 total —
-- accumulated test debt going back further than this session, cleaned up
-- separately before this migration ran.
--
-- ON DELETE CASCADE matches the actual relationship: a `user_profiles`
-- row has no meaning without its `users` row (it's display data FOR an
-- account, not an independent entity), so deleting the account should
-- always take its display row with it — not leave orphaned display data
-- pointing at nothing.

ALTER TABLE public.user_profiles
  ADD CONSTRAINT user_profiles_id_fkey
  FOREIGN KEY (id) REFERENCES public.users (id) ON DELETE CASCADE;

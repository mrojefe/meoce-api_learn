-- JF's direct instruction: stop using NULL/unlimited anywhere in
-- plan_features/subscription_features/user_features -- every limit-kind
-- feature must carry a real, bounded integer, never null. This replaces
-- the "null means unlimited" convention this schema used before, not just
-- adds a column for newly-purchased grants (that was
-- 20260913030000_add_purchase_grant_value_to_features.sql -- this
-- migration is the wider one: it rewrites EXISTING null values too).
--
-- 999999 is the same placeholder sentinel used there -- a deliberately
-- large-but-finite number, not a tuned business value. JF should replace
-- these with real per-feature/per-plan numbers whenever the actual caps
-- are decided; this migration only removes null from the data, it does
-- not claim 999999 is the right cap for anything.
--
-- Covers all three places a limit-kind feature's value is ever stored:
-- plan_features (a plan's definition), subscription_features (a
-- subscription's frozen snapshot -- future snapshots will already carry a
-- real number automatically once plan_features has none left, but this
-- also fixes any snapshot already taken before that), and user_features
-- (individual grants). Only rows for kind='limit' features are touched --
-- a boolean-kind feature's null would mean something else entirely
-- (unset), never touched here.

UPDATE plan_features
SET value = to_jsonb(999999)
WHERE value = 'null'::jsonb
  AND feature_key IN (SELECT key FROM features WHERE kind = 'limit');

UPDATE subscription_features
SET value_snapshot = to_jsonb(999999)
WHERE value_snapshot = 'null'::jsonb
  AND feature_key IN (SELECT key FROM features WHERE kind = 'limit');

UPDATE user_features
SET value = to_jsonb(999999)
WHERE value = 'null'::jsonb
  AND feature_key IN (SELECT key FROM features WHERE kind = 'limit');

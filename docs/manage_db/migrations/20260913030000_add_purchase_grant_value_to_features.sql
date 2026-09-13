-- Adds the missing catalog information JF pointed out was actually missing:
-- not "nowhere to store a purchased value" (plan_features/user_features.value
-- is jsonb, already stores any value -- proven by every existing limit-kind
-- plan_features row) but "nothing states what NUMBER a purchased limit-kind
-- feature grants." NULL (this codebase's existing "unlimited" convention,
-- used throughout plan_features for whole-plan grants) was rejected on
-- purpose for this: a standalone addon purchase should grant a real,
-- concrete, bounded number, not literal unlimited.
--
-- purchase_grant_value is nullable at the column level only because it does
-- not apply to boolean-kind features (their grant is unambiguous: true,
-- decided in code, never looked up here) -- every ACTIVE, PRICED limit-kind
-- feature gets a real integer, never null, so a purchase can never silently
-- grant "unlimited" by omission.
--
-- 999999 is a deliberate placeholder sentinel ("big int"), not a tuned
-- business number -- JF should replace these with real per-feature values
-- when addon pricing is actually decided. Today every feature is still
-- priced at 0 XOF (verified against meoce_prod, 2026-09-13), so nothing is
-- actually purchasable yet regardless of this column's values.

ALTER TABLE features ADD COLUMN purchase_grant_value jsonb;

COMMENT ON COLUMN features.purchase_grant_value IS
    'What a standalone addon purchase (or a custom plan built from this '
    'feature) grants for a limit-kind feature -- a real, bounded integer, '
    'never null/unlimited. Unused (stays NULL) for boolean-kind features, '
    'whose grant is unambiguously true.';

UPDATE features
SET purchase_grant_value = to_jsonb(999999)
WHERE kind = 'limit' AND is_active = true;

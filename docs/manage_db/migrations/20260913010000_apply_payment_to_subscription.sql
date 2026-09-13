-- Credits one paid, provider-verified plan payment onto the caller's
-- subscription, atomically. Adapted from real prod's function of the same
-- name -- that version is written against `user_id`; this database's
-- `subscriptions`/`payments`/`subscription_features` tables use `account_id`,
-- so every reference is renamed to match.
--
-- REVIEW: this function is the actual money-crediting logic -- please read it.
-- Called from app/services/billing.py's _credit_plan(), only after the
-- payment's status has been confirmed against GeniusPay itself (never from
-- the webhook payload alone in production), and only after the caller's
-- anti-downgrade check in Python has already passed (this function does not
-- re-check that -- it trusts its caller to have already decided this
-- payment SHOULD be applied).
--
-- `subscriptions` has no UNIQUE constraint on account_id (checked directly
-- against meoce_prod, 2026-09-13) -- unlike real prod's schema, a plain
-- ON CONFLICT upsert is not available here. This function instead locks any
-- existing row for the account with SELECT ... FOR UPDATE and either UPDATEs
-- it or INSERTs a fresh one, inside one transaction, so two concurrent
-- deliveries for the same payment cannot both create a duplicate row or both
-- extend the period.
--
-- Also sets price_snapshot ("frozen total actually paid" per the design) and
-- refreshes subscription_features: DELETE then a fresh INSERT from the just-
-- purchased plan's plan_features -- never a plain upsert, so a later edit to
-- plan_features cannot silently change what an already-paying subscriber is
-- entitled to; entitlements.py reads this snapshot, not a live join.
--
-- GET DIAGNOSTICS after the UPDATE on `payments` catches the case where a
-- second delivery arrives after the first already applied: the
-- `WHERE applied = false` guard means the UPDATE matches zero rows the
-- second time, and this function returns early instead of crediting twice.

CREATE OR REPLACE FUNCTION apply_payment_to_subscription(
    p_payment_id uuid,
    p_months integer DEFAULT 1
) RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_payment record;
    v_rows_updated integer;
    v_existing_sub_id uuid;
    v_current_period_end timestamptz;
    v_new_period_end timestamptz;
    v_sub_id uuid;
BEGIN
    -- Claim this payment: only one caller gets past this UPDATE per payment.
    UPDATE payments
    SET applied = true, applied_at = now()
    WHERE id = p_payment_id
      AND applied = false
      AND status = 'completed'
    RETURNING account_id, plan_code, periods_purchased, amount_xof
    INTO v_payment;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

    IF v_rows_updated = 0 THEN
        RETURN jsonb_build_object(
            'applied', false,
            'reason', 'payment already applied, not completed, or does not exist'
        );
    END IF;

    -- Lock any existing subscription row for this account.
    SELECT id, current_period_end INTO v_existing_sub_id, v_current_period_end
    FROM subscriptions
    WHERE account_id = v_payment.account_id
    ORDER BY created_at DESC
    LIMIT 1
    FOR UPDATE;

    v_new_period_end := GREATEST(now(), COALESCE(v_current_period_end, now()))
        + ((p_months * v_payment.periods_purchased)::text || ' months')::interval;

    IF v_existing_sub_id IS NOT NULL THEN
        UPDATE subscriptions
        SET plan_code = v_payment.plan_code,
            status = 'active',
            price_snapshot = v_payment.amount_xof,
            current_period_end = v_new_period_end,
            cancelled_at = NULL,
            cancellation_reason = NULL,
            payment_provider = 'geniuspay',
            updated_at = now()
        WHERE id = v_existing_sub_id;
        v_sub_id := v_existing_sub_id;
    ELSE
        INSERT INTO subscriptions (
            account_id, plan_code, status, price_snapshot, current_period_start,
            current_period_end, payment_provider
        )
        VALUES (
            v_payment.account_id, v_payment.plan_code, 'active', v_payment.amount_xof,
            now(), v_new_period_end, 'geniuspay'
        )
        RETURNING id INTO v_sub_id;
    END IF;

    -- Snapshot the plan's CURRENT features onto the subscription. Never a
    -- plain upsert: delete then insert, so a feature the plan no longer has
    -- does not linger.
    DELETE FROM subscription_features WHERE subscription_id = v_sub_id;

    INSERT INTO subscription_features (subscription_id, feature_key, value_snapshot, snapshotted_at)
    SELECT v_sub_id, feature_key, value, now()
    FROM plan_features
    WHERE plan_code = v_payment.plan_code;

    RETURN jsonb_build_object(
        'applied', true,
        'account_id', v_payment.account_id,
        'plan_code', v_payment.plan_code,
        'current_period_end', v_new_period_end
    );
END;
$$;

-- Credits one paid, provider-verified addon payment onto the caller's
-- user_features grant, atomically. New function -- addons are a purchase
-- path that did not exist before this pass.
--
-- REVIEW: this function is the actual money-crediting logic -- please read it.
-- Called from app/services/purchasing.py's _credit_addon(), same trust
-- boundary as apply_payment_to_subscription(): only called after the
-- payment's status has been confirmed against GeniusPay itself.
--
-- user_features' primary key is (account_id, feature_key, source) -- this
-- function always writes source='addon', so a plan-granted feature
-- (source='plan', if that is ever introduced) and an admin override
-- (source='support', say) can coexist with an addon grant on the same key
-- without conflicting.
--
-- expires_at is EXTENDED, not reset: GREATEST(now(), existing expires_at)
-- plus this purchase's duration -- buying more time while an addon is
-- already active adds to what is left, it does not restart from now and
-- waste the remainder, same principle as the subscription period extension.
--
-- Granted VALUE depends on the feature's kind: true for boolean-kind,
-- 999999 (same placeholder as app/services/purchasing.py's
-- DEFAULT_LIMIT_GRANT_VALUE and migration 20260913040000's null rewrite)
-- for limit-kind. Written straight into user_features' existing jsonb
-- value column -- no separate catalog column needed for this, ever.

CREATE OR REPLACE FUNCTION apply_payment_to_addon(
    p_payment_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_payment record;
    v_rows_updated integer;
    v_feature record;
    v_extension interval;
    v_granted_value jsonb;
    v_existing_expires_at timestamptz;
    v_new_expires_at timestamptz;
BEGIN
    UPDATE payments
    SET applied = true, applied_at = now()
    WHERE id = p_payment_id
      AND applied = false
      AND status = 'completed'
    RETURNING account_id, addon_code, periods_purchased
    INTO v_payment;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

    IF v_rows_updated = 0 THEN
        RETURN jsonb_build_object(
            'applied', false,
            'reason', 'payment already applied, not completed, or does not exist'
        );
    END IF;

    SELECT interval, interval_count, kind INTO v_feature
    FROM features WHERE key = v_payment.addon_code;

    IF v_feature.kind = 'boolean' THEN
        v_granted_value := 'true'::jsonb;
    ELSE
        v_granted_value := to_jsonb(999999);
    END IF;

    v_extension := ((v_feature.interval_count * v_payment.periods_purchased)::text
        || ' ' || (CASE WHEN v_feature.interval = 'week' THEN 'weeks' ELSE 'months' END))::interval;

    SELECT expires_at INTO v_existing_expires_at
    FROM user_features
    WHERE account_id = v_payment.account_id
      AND feature_key = v_payment.addon_code
      AND source = 'addon'
    FOR UPDATE;

    v_new_expires_at := GREATEST(now(), COALESCE(v_existing_expires_at, now())) + v_extension;

    INSERT INTO user_features (account_id, feature_key, source, value, source_ref, granted_at, expires_at)
    VALUES (v_payment.account_id, v_payment.addon_code, 'addon', v_granted_value,
            p_payment_id::text, now(), v_new_expires_at)
    ON CONFLICT (account_id, feature_key, source) DO UPDATE
        SET value = v_granted_value,
            expires_at = v_new_expires_at,
            source_ref = p_payment_id::text,
            updated_at = now();

    RETURN jsonb_build_object(
        'applied', true,
        'account_id', v_payment.account_id,
        'feature_key', v_payment.addon_code,
        'value', v_granted_value,
        'expires_at', v_new_expires_at
    );
END;
$$;

-- Custom plans + independent addons, uniform pricing.
--
-- Designed over a long session (2026-09-04): synthesized from 2 independent
-- DB-aware agent proposals, JF's own requirements, and an independent review
-- against this live schema before being applied. Full picture + lifecycle
-- flowchart on Miro board "meo". Design notes in
-- meoce_course/meoce_api/CUSTOM_PLANS_DESIGN.md.
--
-- What changes, and why:
--   1. subscription_plans -> plans, +kind ('fixed'/'custom'), +owner_user_id.
--      A custom plan is just another row here, riding the exact same
--      apply_payment_to_subscription() pipeline as a fixed plan.
--   2. The JSONB `features` blob (no DB-level integrity — a typo'd key was
--      invisible to Postgres) is replaced by plan_features, a real join
--      table FK'd to the features catalog.
--   3. Every plan/feature gets a UNIFORM price_xof + interval + interval_count
--      triplet, always set, never conditionally meaningful — replaces the
--      monthly_price_xof/yearly_price_xof pair, which couldn't express a
--      custom plan's price at all.
--   4. subscription_features snapshots what a subscription grants at
--      subscribe/renew/plan-change time, so editing plan_features later (or
--      a user editing their own custom plan) can't retroactively change what
--      an existing paying subscriber already agreed to mid-period.
--   5. payments gains addon_code (alongside the now-nullable plan_code) and
--      periods_purchased, with a CHECK enforcing exactly one of
--      plan_code/addon_code — a payment is for a plan XOR one addon.
--   6. user_features is left as-is: it's already the right shape for
--      individual addon grants (source='addon'), just never used yet.

-- ── 1. plans (renamed from subscription_plans) ─────────────────────────────

ALTER TABLE subscription_plans RENAME TO plans;

ALTER TABLE plans
  ADD COLUMN kind TEXT NOT NULL DEFAULT 'fixed' CHECK (kind IN ('fixed', 'custom')),
  ADD COLUMN owner_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  ADD COLUMN price_xof NUMERIC,
  ADD COLUMN interval TEXT CHECK (interval IN ('week', 'month')),
  ADD COLUMN interval_count INT NOT NULL DEFAULT 1 CHECK (interval_count > 0);

-- Backfill the 4 existing plans (free/plus/pro/premium) onto the new shape.
-- Every plan gets a real price_xof — 0 for the null-priced ones (free,
-- premium), not left null. "Never conditionally meaningful" applies to the
-- data too, not just the column definition.
UPDATE plans
   SET price_xof = COALESCE(monthly_price_xof, 0),
       interval = 'month';

ALTER TABLE plans ALTER COLUMN price_xof SET NOT NULL;
ALTER TABLE plans ALTER COLUMN interval SET NOT NULL;

-- ── 2. plan_features — replaces the JSONB blob ─────────────────────────────

CREATE TABLE plan_features (
  plan_code   TEXT  NOT NULL REFERENCES plans(code) ON DELETE CASCADE,
  feature_key TEXT  NOT NULL REFERENCES features(key),
  value       JSONB NOT NULL,
  PRIMARY KEY (plan_code, feature_key)
);

-- Backfill from the old JSONB blob. A key that doesn't exist in the real
-- features catalog is silently dropped here (the FK would reject it anyway)
-- — this is the exact drift the redesign exists to prevent going forward;
-- historically-bad keys are lost on migration, not carried into the new
-- integrity-checked table. (Known live example checked before this
-- migration: a plan referencing "news_feed", which has no features row.)
INSERT INTO plan_features (plan_code, feature_key, value)
SELECT p.code, kv.key, kv.value
  FROM plans p, jsonb_each(p.features) AS kv
 WHERE EXISTS (SELECT 1 FROM features f WHERE f.key = kv.key);

-- Pre-existing drift, found only after this migration ran: the Python
-- PlanFeatures schema declares `news_feed` (every plan grants it), but the
-- features catalog never had a row for it — so the WHERE EXISTS filter
-- above correctly, but silently, dropped it. Root cause: a Python-side field
-- that was never given a matching catalog row when it was added. Fixing the
-- catalog here, then backfilling plan_features for it from the same
-- knowledge the Python docstring already states ("every plan grants it
-- today"), since the source JSONB is dropped by the time this is caught.
INSERT INTO features (key, label, description, kind, free_default, anon_default,
                       price_xof, interval, interval_count, category, is_active, display_order)
VALUES ('news_feed', 'News feed', 'Read the news feed at all. Every plan grants it today.',
        'boolean', 'true'::jsonb, 'true'::jsonb, 0, 'week', 1, 'data', true, 0);

INSERT INTO plan_features (plan_code, feature_key, value)
SELECT code, 'news_feed', 'true'::jsonb FROM plans;

-- multi_layout is the opposite drift — a catalog row (is_active=false) for a
-- field Python already removed from PlanFeatures in an earlier session. Left
-- alone deliberately: referenced by no plan (plan_features has 0 rows for
-- it), already marked inactive, no data to migrate, no harm sitting there.

ALTER TABLE plans DROP COLUMN features;
ALTER TABLE plans DROP COLUMN monthly_price_xof;
ALTER TABLE plans DROP COLUMN yearly_price_xof;

-- ── 3. features — same uniform pricing triplet ─────────────────────────────

ALTER TABLE features
  ADD COLUMN price_xof NUMERIC,
  ADD COLUMN interval TEXT CHECK (interval IN ('week', 'month')),
  ADD COLUMN interval_count INT NOT NULL DEFAULT 1 CHECK (interval_count > 0);

UPDATE features
   SET price_xof = COALESCE(unit_price_xof, 0),
       interval = 'week';

ALTER TABLE features ALTER COLUMN price_xof SET NOT NULL;
ALTER TABLE features ALTER COLUMN interval SET NOT NULL;
ALTER TABLE features DROP COLUMN unit_price_xof;

-- ── 4. subscriptions — price snapshot ──────────────────────────────────────

ALTER TABLE subscriptions
  ADD COLUMN price_snapshot NUMERIC;

-- ── 5. subscription_features — frozen per-subscription grant snapshot ─────

CREATE TABLE subscription_features (
  subscription_id UUID        NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
  feature_key     TEXT        NOT NULL REFERENCES features(key),
  value_snapshot  JSONB       NOT NULL,
  snapshotted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (subscription_id, feature_key)
);

-- ── 6. payments — addon target + duration ──────────────────────────────────

ALTER TABLE payments
  ALTER COLUMN plan_code DROP NOT NULL,
  ADD COLUMN addon_code TEXT REFERENCES features(key),
  ADD COLUMN periods_purchased INT NOT NULL DEFAULT 1 CHECK (periods_purchased > 0),
  ADD CONSTRAINT payments_exactly_one_target
      CHECK ((plan_code IS NOT NULL) <> (addon_code IS NOT NULL));

-- ── 7. Keep apply_payment_to_subscription() working after the rename ──────
--
-- MINIMAL patch only: subscription_plans -> plans, monthly_price_xof ->
-- price_xof. Everything else (the p_months hardcoding, no
-- subscription_features snapshot, no periods_purchased/interval awareness)
-- is UNCHANGED here on purpose — this migration's job is "don't break the
-- live payment function", not "finish the redesign". The interval-aware
-- period calculation and the subscription_features re-snapshot on
-- apply/renew are real follow-up work, done deliberately and tested
-- separately, not folded into a structural rename.

CREATE OR REPLACE FUNCTION public.apply_payment_to_subscription(p_payment_id uuid, p_months integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pay           public.payments%ROWTYPE;
  v_sub_id        UUID;
  v_period_end    TIMESTAMPTZ;
  v_base          TIMESTAMPTZ;
  v_now           TIMESTAMPTZ := now();
  v_marked        INT;
  v_current_plan  TEXT;
  v_current_price NUMERIC := 0;
  v_new_price     NUMERIC := 0;
BEGIN
  -- Verrou de ligne : sérialise deux webhooks concurrents sur le même paiement.
  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'payment_not_found');
  END IF;

  -- Idempotence : déjà crédité → on ne refait rien (et ce n'est pas une erreur).
  IF v_pay.applied THEN
    RETURN jsonb_build_object('ok', true, 'already_applied', true);
  END IF;

  -- Abonnement actif courant (tout user en a un : trigger 'free' à l'inscription).
  SELECT id, current_period_end, plan_code INTO v_sub_id, v_base, v_current_plan
    FROM public.subscriptions
   WHERE user_id = v_pay.user_id
     AND status IN ('trial', 'active')
   ORDER BY started_at DESC
   LIMIT 1
   FOR UPDATE;

  -- ── Protection ANTI-DÉCLASSEMENT ────────────────────────────────────────────
  SELECT COALESCE(price_xof, 0) INTO v_current_price
    FROM public.plans WHERE code = v_current_plan;
  SELECT COALESCE(price_xof, 0) INTO v_new_price
    FROM public.plans WHERE code = v_pay.plan_code;

  IF v_current_plan IS DISTINCT FROM v_pay.plan_code
     AND v_current_price > v_new_price
     AND (v_base IS NOT NULL AND v_base > v_now)  -- son plan supérieur court encore
  THEN
    INSERT INTO public.payment_events (
      payment_id, reference, event_type, status, source, amount_xof, note
    ) VALUES (
      p_payment_id, v_pay.reference, 'downgrade_blocked', NULL, 'server',
      v_pay.amount_xof,
      format('Déclassement refusé : plan actif %s (%s XOF) > plan payé %s (%s XOF), actif jusqu''au %s. Paiement NON appliqué — à traiter par le support.',
             v_current_plan, v_current_price, v_pay.plan_code, v_new_price, v_base)
    );
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'downgrade_blocked',
      'current_plan', v_current_plan,
      'paid_plan', v_pay.plan_code
    );
  END IF;

  IF v_base IS NULL OR v_base <= v_now THEN
    v_base := v_now;
  END IF;
  v_period_end := v_base + (p_months || ' month')::interval;

  IF v_sub_id IS NOT NULL THEN
    UPDATE public.subscriptions
       SET plan_code                = v_pay.plan_code,
           status                   = 'active',
           current_period_start     = v_now,
           current_period_end       = v_period_end,
           cancelled_at             = NULL,
           cancellation_reason      = NULL,
           payment_provider         = v_pay.provider,
           external_subscription_id = v_pay.reference
     WHERE id = v_sub_id;
  ELSE
    INSERT INTO public.subscriptions (
      user_id, plan_code, status, current_period_start, current_period_end,
      payment_provider, external_subscription_id
    ) VALUES (
      v_pay.user_id, v_pay.plan_code, 'active', v_now, v_period_end,
      v_pay.provider, v_pay.reference
    );
  END IF;

  -- Marqueur d'application — gardé par `applied = false` (double sécurité).
  UPDATE public.payments
     SET applied = true, applied_at = v_now
   WHERE id = p_payment_id AND applied = false;
  GET DIAGNOSTICS v_marked = ROW_COUNT;

  IF v_marked = 0 THEN
    -- Un concurrent a gagné la course : on annule TOUT (atomicité).
    RAISE EXCEPTION 'concurrent_apply_detected';
  END IF;

  -- Trace ledger du crédit effectif (même transaction).
  INSERT INTO public.payment_events (
    payment_id, reference, event_type, status, source, amount_xof, note
  ) VALUES (
    p_payment_id, v_pay.reference, 'subscription_credited', 'completed', 'server',
    v_pay.amount_xof,
    format('Abonnement %s crédité jusqu''au %s', v_pay.plan_code, v_period_end)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'plan_code', v_pay.plan_code,
    'current_period_end', v_period_end
  );
END;
$function$;

-- ── 8. Keep get_user_entitlements() working after the rename ──────────────
--
-- Same minimal-patch philosophy: reads plan_features directly instead of the
-- dropped sp.features JSONB. Still NOT reading subscription_features (the
-- frozen snapshot) — that's the same deferred follow-up work as above.

CREATE OR REPLACE FUNCTION public.get_user_entitlements(p_user uuid, p_is_anon boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT COALESCE(
    jsonb_object_agg(
      f.key,
      CASE
        WHEN p_is_anon THEN f.anon_default
        ELSE COALESCE(uf_eff.value, plan_eff.value, f.free_default)
      END
    ),
    '{}'::jsonb
  )
  FROM features f
  LEFT JOIN LATERAL (
    SELECT uf.value
    FROM user_features uf
    WHERE uf.user_id = p_user
      AND uf.feature_key = f.key
      AND (uf.expires_at IS NULL OR uf.expires_at > now())
    ORDER BY uf.granted_at DESC
    LIMIT 1
  ) uf_eff ON true
  LEFT JOIN LATERAL (
    SELECT pf.value
    FROM subscriptions s
    JOIN plan_features pf ON pf.plan_code = s.plan_code AND pf.feature_key = f.key
    WHERE s.user_id = p_user
      AND s.status = 'active'
    ORDER BY s.current_period_start DESC
    LIMIT 1
  ) plan_eff ON true
  WHERE f.is_active;
$function$;

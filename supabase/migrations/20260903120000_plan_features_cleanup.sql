-- Plan features: remove the dead keys, make every plan explicit.
--
-- Three problems, found 2026-09-02 by tracing every key of
-- subscription_plans.features through the API and the frontend.
--
-- 1. DEAD KEYS. `multi_layout` was superseded by `max_chart_panes` — a number,
--    which can express 1, 2 or 4 panes where a boolean cannot. The frontend
--    comment at ChartLayoutManager.tsx:32 says so explicitly. Nothing in either
--    repo reads it any more. `history_years_default` is read by nobody at all.
--
-- 2. IMPLICIT VALUES. `intraday_granular_timeframes` is absent from free and
--    plus. The effect happens to be right — a missing key reads as falsy, so
--    they are denied — but by accident rather than by decision. A key that is
--    absent means "unlimited" for a limit and "no" for a switch: the same
--    silence, opposite meanings. Every plan should say every key.
--
-- 3. A PRICING INVERSION. max_real_portfolios is 2 on free and 1 on plus: a
--    customer paying 8 500 XOF/month gets less than a free one.
--    ⚠ The value below is a placeholder chosen to stop the inversion, NOT a
--    pricing decision. Revisit before this reaches production.
--
-- Staging only. Production is not ready for this.

-- Note: the key-existence operator is written as jsonb_exists(...) rather than
-- the usual `?`, because `?` is a parameter placeholder in several drivers and
-- gets mangled before Postgres sees it. The function form means the same thing
-- and travels safely through any client.

BEGIN;

-- 1. drop the dead keys everywhere
UPDATE public.subscription_plans
SET    features = features - 'multi_layout' - 'history_years_default'
WHERE  jsonb_exists(features, 'multi_layout')
   OR  jsonb_exists(features, 'history_years_default');

-- 2. state the switch explicitly where it was only implied
--    (|| merges; the right-hand side wins, so this is a no-op where already set)
UPDATE public.subscription_plans
SET    features = jsonb_build_object('intraday_granular_timeframes', false) || features
WHERE  NOT jsonb_exists(features, 'intraday_granular_timeframes');

-- 3. stop the inversion: plus must not be below free
UPDATE public.subscription_plans
SET    features = features || jsonb_build_object('max_real_portfolios', 2)
WHERE  code = 'plus';

COMMIT;

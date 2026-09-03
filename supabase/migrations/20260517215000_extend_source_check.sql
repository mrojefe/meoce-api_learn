-- ============================================================
-- D131 — Etend daily_candles_source_check pour tracer les
-- transformations post-import (enrichissements, recalculs)
-- ============================================================
-- Contexte :
-- Le constraint actuel n'autorise que 5 valeurs : sikafinance,
-- sgi_eod, boc_pdf, manual, other. Mais on doit pouvoir tracer
-- les operations d'enrichissement post-import :
--   - 'sikafinance+enriched_trade_sec' : enrichi via Excel/OLD DB
--     trade_securities (fix #1, 147 822 rows)
--   - 'sikafinance+recalc_close_x_qty' : value recalculee
--     mathematiquement = close_price * quantity (fix #2,
--     6 702 rows stocks ou source historique sikafinance n'avait
--     ni value ni trade_count)
--
-- Philosophie : tracabilite totale (data philosophy Afriview).
-- Permet a un analyste de distinguer en SQL :
--   - donnee brute sikafinance
--   - donnee enrichie avec trade-securities (precision haute)
--   - donnee recalculee mathematiquement (approximation OHLC flat)
-- ============================================================

ALTER TABLE public.daily_candles
  DROP CONSTRAINT IF EXISTS daily_candles_source_check;

ALTER TABLE public.daily_candles
  ADD CONSTRAINT daily_candles_source_check
  CHECK (source = ANY (ARRAY[
    'sikafinance'::text,
    'sgi_eod'::text,
    'boc_pdf'::text,
    'manual'::text,
    'other'::text,
    'sikafinance+enriched_trade_sec'::text,
    'sikafinance+recalc_close_x_qty'::text
  ]));

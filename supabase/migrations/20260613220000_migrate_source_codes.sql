-- Migration : normalisation des codes source dans daily_candles et daily_volume
--
-- Principe : la colonne `source` ne doit plus contenir de noms lisibles de fournisseurs.
-- Elle stocke désormais des codes opaques définis dans source_registry.py.
-- Le mapping complet est dans :
--   APP/meoce-airflow/dags/workers/source_registry.py
--
-- Valeurs remplacées :
--   "madisinvest"                    → "DS-MD4"
--   "sikafinance"                    → "DS-SK6"
--   "sikafinance+enriched_trade_sec" → "DS-SK6E"
--   "sikafinance+recalc_close_x_qty" → "DS-SK6R"
--   "bfin.brvm.org"                  → "DS-BF2"
--
-- Ancienne contrainte daily_candles_source_check :
--   ('sikafinance', 'sgi_eod', 'boc_pdf', 'manual', 'other',
--    'sikafinance+enriched_trade_sec', 'sikafinance+recalc_close_x_qty',
--    'madisinvest', 'madisinvest+bfin')

-- ── Étape 1 : supprimer l'ancienne contrainte CHECK sur daily_candles ─────────

ALTER TABLE daily_candles DROP CONSTRAINT IF EXISTS daily_candles_source_check;

-- ── Étape 2 : migrer les données daily_candles ────────────────────────────────

UPDATE daily_candles SET source = 'DS-MD4'  WHERE source = 'madisinvest';
UPDATE daily_candles SET source = 'DS-MD4'  WHERE source = 'madisinvest+bfin';
UPDATE daily_candles SET source = 'DS-SK6'  WHERE source = 'sikafinance';
UPDATE daily_candles SET source = 'DS-SK6E' WHERE source = 'sikafinance+enriched_trade_sec';
UPDATE daily_candles SET source = 'DS-SK6R' WHERE source = 'sikafinance+recalc_close_x_qty';
-- 'sgi_eod', 'boc_pdf', 'manual', 'other' → pas de lignes en prod, mais on les mappe quand même
UPDATE daily_candles SET source = 'DS-SA5'  WHERE source = 'sgi_eod';
UPDATE daily_candles SET source = 'DS-BC3'  WHERE source = 'boc_pdf';

-- ── Étape 3 : poser la nouvelle contrainte avec les codes DS-* ────────────────

ALTER TABLE daily_candles ADD CONSTRAINT daily_candles_source_check
  CHECK (source = ANY (ARRAY[
    'DS-BV1',   -- brvm.org officiel
    'DS-BF2',   -- bfin.brvm.org volumes
    'DS-BC3',   -- BOC BRVM PDF
    'DS-MD4',   -- madisinvest
    'DS-SA5',   -- sgi-agi intraday
    'DS-SK6',   -- sikafinance brut
    'DS-SK6E',  -- sikafinance + enriched_trade_sec
    'DS-SK6R',  -- sikafinance + recalc_close_x_qty
    'DS-RB7',   -- richbourse
    'manual',   -- saisie manuelle (conserver pour cas d'usage support)
    'other'     -- fallback explicite
  ]));

-- ── Étape 4 : migrer les données daily_volume ─────────────────────────────────
-- (daily_volume n'a pas de CHECK constraint sur source)

UPDATE daily_volume SET source = 'DS-SK6E' WHERE source = 'sikafinance+enriched_trade_sec';
UPDATE daily_volume SET source = 'DS-SK6R' WHERE source = 'sikafinance+recalc_close_x_qty';
UPDATE daily_volume SET source = 'DS-BF2'  WHERE source = 'bfin.brvm.org';

-- ── Vérification post-migration ───────────────────────────────────────────────
-- SELECT source, count(*) FROM daily_candles GROUP BY source ORDER BY count DESC;
-- SELECT source, count(*) FROM daily_volume   GROUP BY source ORDER BY count DESC;

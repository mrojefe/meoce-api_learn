-- Fix du fallback bond_candles ajouté en 20260812100000 (2026-08-12, JF —
-- toujours 0.00 en watchlist pour de nombreuses obligations malgré le fallback).
--
-- Bug : le fallback n'était déclenché que pour un instrument SANS AUCUNE ligne
-- dans intraday_snapshots à la date la plus récente. Or le worker intraday scanne
-- TOUS les instruments chaque cycle (y compris ceux sans trade) — une obligation
-- illiquide a donc presque toujours une ligne dans intraday_snapshots pour
-- aujourd'hui, mais avec last_trade_price NULL (aucun trade). Ces lignes
-- "existent mais sont inutilisables" passaient à travers le NOT IN et ne
-- déclenchaient jamais le fallback. Correction : on COALESCE le prix par ligne
-- (fallback dès que last_trade_price est NULL, pas seulement quand la ligne
-- elle-même est absente), au lieu d'exclure par simple présence d'instrument_id.
CREATE OR REPLACE FUNCTION get_market_snapshot_v2()
RETURNS TABLE(
  instrument_id uuid,
  last_trade_price numeric,
  quantity_cumul  bigint,
  value_cumul     numeric,
  scraped_at      timestamptz,
  previous_close  numeric,
  market_date     date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH latest AS (
    SELECT MAX(market_date) AS d FROM intraday_snapshots
  ),
  latest_per_instrument AS (
    SELECT DISTINCT ON (s.instrument_id)
      s.instrument_id,
      s.last_trade_price,
      s.quantity_cumul,
      s.value_cumul,
      s.scraped_at,
      l.d AS market_date
    FROM latest l
    JOIN intraday_snapshots s ON s.market_date = l.d
    ORDER BY s.instrument_id, s.scraped_at DESC
  ),
  bond_fallback AS (
    SELECT DISTINCT ON (bc.instrument_id)
      bc.instrument_id,
      bc.close_price AS last_trade_price,
      bc.date AS market_date
    FROM bond_candles bc
    JOIN instruments i ON i.id = bc.instrument_id AND i.type IN ('bond', 'sukuk')
    WHERE bc.close_price IS NOT NULL
    ORDER BY bc.instrument_id, bc.date DESC
  )
  SELECT
    li.instrument_id,
    -- Prix utilisable = celui de la ligne intraday si non-NULL, SINON le
    -- dernier close_price BOC connu (que la ligne intraday existe ou non).
    COALESCE(li.last_trade_price, bf.last_trade_price) AS last_trade_price,
    li.quantity_cumul,
    li.value_cumul,
    COALESCE(li.scraped_at, bf.market_date::timestamptz) AS scraped_at,
    m.previous_close,
    COALESCE(li.market_date, bf.market_date) AS market_date
  FROM latest_per_instrument li
  LEFT JOIN intraday_meta_data m
    ON m.instrument_id = li.instrument_id
    AND m.market_date = li.market_date
  LEFT JOIN bond_fallback bf ON bf.instrument_id = li.instrument_id
  UNION ALL
  -- Instruments bond/sukuk totalement absents d'intraday_snapshots aujourd'hui
  -- (pas même une ligne à prix NULL) : couverts séparément ici.
  SELECT
    bf.instrument_id,
    bf.last_trade_price,
    NULL::bigint AS quantity_cumul,
    NULL::numeric AS value_cumul,
    bf.market_date::timestamptz AS scraped_at,
    NULL::numeric AS previous_close,
    bf.market_date
  FROM bond_fallback bf
  WHERE bf.instrument_id NOT IN (SELECT instrument_id FROM latest_per_instrument)
$$;

GRANT EXECUTE ON FUNCTION get_market_snapshot_v2() TO anon, authenticated;

-- RPC get_market_snapshot_v2 : fusionne les 3 requêtes séquentielles
-- (latest_date + intraday_meta + latest_snapshot) en un seul appel Postgres.
-- Remplace les étapes 2+3+4 de services/market.py get_snapshot().

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
  )
  SELECT
    li.instrument_id,
    li.last_trade_price,
    li.quantity_cumul,
    li.value_cumul,
    li.scraped_at,
    m.previous_close,
    li.market_date
  FROM latest_per_instrument li
  LEFT JOIN intraday_meta_data m
    ON m.instrument_id = li.instrument_id
    AND m.market_date = li.market_date
$$;

GRANT EXECUTE ON FUNCTION get_market_snapshot_v2() TO anon, authenticated;

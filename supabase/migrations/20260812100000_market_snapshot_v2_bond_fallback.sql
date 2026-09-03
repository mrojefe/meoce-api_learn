-- Watchlist "Dernier" toujours à 0.00 pour les obligations (2026-08-12, JF).
--
-- get_market_snapshot_v2 ne renvoie une ligne QUE pour un instrument ayant un
-- snapshot intraday à la date la PLUS RÉCENTE en base (`latest_per_instrument`,
-- JOIN sans fallback). La grande majorité des obligations sont illiquides et ne
-- tradent pas tous les jours : elles n'ont donc JAMAIS de ligne dans ce RPC, donc
-- jamais de prix — /api/market/live les droppe silencieusement
-- (`if (price == null) continue`) et la watchlist retombe sur son 0.00 final
-- (WatchlistPanel.tsx: `s.currentPrice || s.close || lastCandle?.close || 0`).
--
-- Le fix récent (market/live/route.ts, inclure bond dans le mapping id→symbole)
-- résout seulement le cas d'une obligation ayant tradé AUJOURD'HUI — insuffisant.
--
-- Ce correctif ajoute un fallback : pour tout instrument bond/sukuk SANS ligne
-- dans latest_per_instrument, on renvoie son dernier close_price connu
-- (bond_candles, la même donnée BOC que le graphe utilise déjà). Pas de volume
-- (quantity_cumul/value_cumul NULL — c'est le rôle du fix "volume obligations"
-- séparé côté graphe, pas de la watchlist).
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
      NULL::bigint AS quantity_cumul,
      NULL::numeric AS value_cumul,
      bc.date::timestamptz AS scraped_at,
      bc.date AS market_date
    FROM bond_candles bc
    JOIN instruments i ON i.id = bc.instrument_id AND i.type IN ('bond', 'sukuk')
    WHERE bc.close_price IS NOT NULL
      AND bc.instrument_id NOT IN (SELECT instrument_id FROM latest_per_instrument)
    ORDER BY bc.instrument_id, bc.date DESC
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
  UNION ALL
  SELECT
    bf.instrument_id,
    bf.last_trade_price,
    bf.quantity_cumul,
    bf.value_cumul,
    bf.scraped_at,
    NULL::numeric AS previous_close,
    bf.market_date
  FROM bond_fallback bf
$$;

GRANT EXECUTE ON FUNCTION get_market_snapshot_v2() TO anon, authenticated;

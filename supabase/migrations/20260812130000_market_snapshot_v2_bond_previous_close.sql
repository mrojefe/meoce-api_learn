-- %Chg incohérent pour les obligations (2026-08-12, JF — Chg=+0,00 mais
-- %Chg=+6899% par ex.). Cause : intraday_meta_data.previous_close vient du flux
-- SGI live (`previousClosingPrice`, worker_intraday.py:173) — un champ non fiable
-- pour les obligations illiquides (valeurs incohérentes avec le vrai prix BOC :
-- ex. TPCI.O94 previous_close=98 alors que last_trade_price=9800). "Dernier" et
-- "%Chg" utilisaient deux sources totalement indépendantes pour les obligations,
-- l'une correcte (bond_candles, cf. fix 20260812100000/120000), l'autre non.
--
-- Fix : pour bond/sukuk, previous_close vient désormais du close_price de la
-- SEANCE BOC PRÉCÉDENTE (bond_candles, même source que "Dernier"), jamais du
-- flux SGI. Stocks inchangés (previous_close reste intraday_meta_data comme avant).
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
  ),
  -- 2ᵉ close_price le plus récent (la séance BOC PRÉCÉDANT celle utilisée comme
  -- "Dernier"), uniquement pour bond/sukuk — même logique de "clôture de la veille"
  -- que le daily pour les actions, mais sourcée BOC au lieu du flux SGI.
  bond_previous_close AS (
    SELECT instrument_id, close_price AS previous_close
    FROM (
      SELECT
        bc.instrument_id,
        bc.close_price,
        ROW_NUMBER() OVER (PARTITION BY bc.instrument_id ORDER BY bc.date DESC) AS rn
      FROM bond_candles bc
      JOIN instruments i ON i.id = bc.instrument_id AND i.type IN ('bond', 'sukuk')
      WHERE bc.close_price IS NOT NULL
    ) ranked
    WHERE rn = 2
  )
  SELECT
    li.instrument_id,
    COALESCE(li.last_trade_price, bf.last_trade_price) AS last_trade_price,
    li.quantity_cumul,
    li.value_cumul,
    -- market_date doit refléter la date RÉELLE du prix retourné : quand li n'a
    -- pas de prix utilisable et qu'on retombe sur bf (BOC), la date doit être
    -- celle de bf (ex. mars), pas celle du snapshot intraday d'aujourd'hui
    -- (qui n'a jamais eu de prix) — sinon un prix vieux de plusieurs mois
    -- s'affiche étiqueté "aujourd'hui".
    CASE WHEN li.last_trade_price IS NULL AND bf.last_trade_price IS NOT NULL
         THEN bf.market_date::timestamptz
         ELSE li.scraped_at
    END AS scraped_at,
    COALESCE(bpc.previous_close, m.previous_close) AS previous_close,
    CASE WHEN li.last_trade_price IS NULL AND bf.last_trade_price IS NOT NULL
         THEN bf.market_date
         ELSE li.market_date
    END AS market_date
  FROM latest_per_instrument li
  LEFT JOIN intraday_meta_data m
    ON m.instrument_id = li.instrument_id
    AND m.market_date = li.market_date
  LEFT JOIN bond_fallback bf ON bf.instrument_id = li.instrument_id
  LEFT JOIN bond_previous_close bpc ON bpc.instrument_id = li.instrument_id
  UNION ALL
  SELECT
    bf.instrument_id,
    bf.last_trade_price,
    NULL::bigint AS quantity_cumul,
    NULL::numeric AS value_cumul,
    bf.market_date::timestamptz AS scraped_at,
    bpc.previous_close,
    bf.market_date
  FROM bond_fallback bf
  LEFT JOIN bond_previous_close bpc ON bpc.instrument_id = bf.instrument_id
  WHERE bf.instrument_id NOT IN (SELECT instrument_id FROM latest_per_instrument)
$$;

GRANT EXECUTE ON FUNCTION get_market_snapshot_v2() TO anon, authenticated;

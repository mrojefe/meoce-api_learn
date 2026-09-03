-- BUG CRITIQUE (2026-08-12, JF — "les prix inquiètent", -99% sur plein d'obligations
-- différentes). Le flux SGI (intraday_snapshots.last_trade_price, worker_intraday.py)
-- représente le prix des OBLIGATIONS en POURCENTAGE DU NOMINAL (ex. 95.0 = 95% de
-- 10000 FCFA), alors que BOC (bond_candles.close_price, notre source PDF officielle)
-- les donne en FCFA ABSOLU (9500.0). Vérifié en base : TPBF.O8 a un close_price BOC
-- constant à ~9500 sur toute la période récente (bond_candles), mais son
-- intraday_snapshots.last_trade_price du jour vaut 95.0 — même titre, même moment,
-- facteur 100 exact. Un facteur QUASI-UNIVERSEL (pas juste pour les illiquides,
-- contrairement au bug previous_close corrigé plus tôt) : DÈS QU'UN COUPON A UN
-- LAST_TRADE_PRICE SGI récent (le titre a un TANTINET d'activité), le fallback
-- COALESCE(li.last_trade_price, bf.last_trade_price) de 20260812100000/120000
-- préférait à tort la valeur SGI (%) à la valeur BOC (FCFA) — d'où le -99% observé
-- sur BEAUCOUP de titres simultanément (prix affiché ÷100 par rapport au vrai prix,
-- previous_close correct lui car déjà sourcé BOC depuis 20260812130000).
--
-- Fix : pour bond/sukuk, ON NE FAIT PLUS JAMAIS CONFIANCE AU FLUX SGI POUR LE PRIX —
-- toujours bond_candles (BOC). intraday_snapshots reste la source pour stocks
-- (aucune anomalie d'échelle constatée là, comportement inchangé).
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
  ),
  is_bond AS (
    SELECT id AS instrument_id FROM instruments WHERE type IN ('bond', 'sukuk')
  )
  SELECT
    li.instrument_id,
    -- bond/sukuk : TOUJOURS bond_candles (BOC, FCFA absolu), jamais le flux SGI
    -- (% du nominal — échelle incompatible). Autres types : comportement inchangé.
    CASE WHEN ib.instrument_id IS NOT NULL
         THEN bf.last_trade_price
         ELSE li.last_trade_price
    END AS last_trade_price,
    li.quantity_cumul,
    li.value_cumul,
    CASE WHEN ib.instrument_id IS NOT NULL
         THEN bf.market_date::timestamptz
         ELSE li.scraped_at
    END AS scraped_at,
    CASE WHEN ib.instrument_id IS NOT NULL
         THEN bpc.previous_close
         ELSE m.previous_close
    END AS previous_close,
    CASE WHEN ib.instrument_id IS NOT NULL
         THEN bf.market_date
         ELSE li.market_date
    END AS market_date
  FROM latest_per_instrument li
  LEFT JOIN is_bond ib ON ib.instrument_id = li.instrument_id
  LEFT JOIN intraday_meta_data m
    ON m.instrument_id = li.instrument_id
    AND m.market_date = li.market_date
  LEFT JOIN bond_fallback bf ON bf.instrument_id = li.instrument_id
  LEFT JOIN bond_previous_close bpc ON bpc.instrument_id = li.instrument_id
  UNION ALL
  -- bond/sukuk totalement absents d'intraday_snapshots aujourd'hui.
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

-- Passage d'un `p_market_date` UNIQUE à une PLAGE `p_date_from`/`p_date_to` pour
-- get_intraday_candles/get_intraday_tick_candles (20260807100100).
--
-- Constat JF (2026-08-09) : les données réelles couvrent 69 séances (27 avril →
-- 6 août, 369k lignes), mais le graphique n'affichait jamais plus d'UNE journée
-- de bougies fines à la fois — pas un bug de permission, une limite d'API : les
-- deux RPC scopaient chaque appel à un seul `market_date`. Les pro/premium ont
-- droit à TOUT l'historique intraday disponible, en continu, pas séance par
-- séance. Signature incompatible (date -> plage) → DROP puis CREATE, pas de
-- CREATE OR REPLACE possible sur un changement de paramètres.

DROP FUNCTION IF EXISTS public.get_intraday_candles(uuid, date, int);
DROP FUNCTION IF EXISTS public.get_intraday_tick_candles(uuid, date, int);

CREATE FUNCTION public.get_intraday_candles(
  p_instrument_id uuid,
  p_date_from date,
  p_date_to date,
  p_bucket_seconds int
)
RETURNS TABLE(
  bucket_start timestamptz,
  open numeric,
  high numeric,
  low numeric,
  close numeric,
  volume bigint,
  value_traded numeric,
  trade_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    to_timestamp(floor(extract(epoch FROM trade_timestamp) / p_bucket_seconds) * p_bucket_seconds) AS bucket_start,
    (array_agg(price ORDER BY trade_timestamp ASC))[1]  AS open,
    max(price) AS high,
    min(price) AS low,
    (array_agg(price ORDER BY trade_timestamp DESC))[1] AS close,
    sum(quantity)::bigint AS volume,
    sum(value) AS value_traded,
    count(*)::bigint AS trade_count
  FROM public.intraday_transactions
  WHERE instrument_id = p_instrument_id
    AND market_date BETWEEN p_date_from AND p_date_to
  GROUP BY 1
  ORDER BY 1;
$$;

-- Bucketing par COMPTEUR de trades, en CONTINU sur toute la plage (pas de reset
-- par jour) : un tick chart n'a pas de notion de "journée", juste une séquence
-- ordonnée de transactions — comportement plus juste qu'un découpage artificiel.
CREATE FUNCTION public.get_intraday_tick_candles(
  p_instrument_id uuid,
  p_date_from date,
  p_date_to date,
  p_tick_size int
)
RETURNS TABLE(
  bucket_id bigint,
  bucket_start timestamptz,
  open numeric,
  high numeric,
  low numeric,
  close numeric,
  volume bigint,
  value_traded numeric,
  trade_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH numbered AS (
    SELECT *,
      ((row_number() OVER (ORDER BY trade_timestamp, seq)) - 1) / p_tick_size AS bucket_id
    FROM public.intraday_transactions
    WHERE instrument_id = p_instrument_id
      AND market_date BETWEEN p_date_from AND p_date_to
  )
  SELECT
    bucket_id,
    min(trade_timestamp) AS bucket_start,
    (array_agg(price ORDER BY trade_timestamp, seq ASC))[1]  AS open,
    max(price) AS high,
    min(price) AS low,
    (array_agg(price ORDER BY trade_timestamp, seq DESC))[1] AS close,
    sum(quantity)::bigint AS volume,
    sum(value) AS value_traded,
    count(*)::bigint AS trade_count
  FROM numbered
  GROUP BY bucket_id
  ORDER BY bucket_id;
$$;

REVOKE ALL ON FUNCTION public.get_intraday_candles(uuid, date, date, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_intraday_candles(uuid, date, date, int) TO service_role;

REVOKE ALL ON FUNCTION public.get_intraday_tick_candles(uuid, date, date, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_intraday_tick_candles(uuid, date, date, int) TO service_role;

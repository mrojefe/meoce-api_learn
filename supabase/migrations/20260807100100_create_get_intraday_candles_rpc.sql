-- Deux RPC d'agrégation pour les timeframes intraday granulaires (tick/minute/
-- heure), construites depuis intraday_transactions (un trade = une ligne,
-- trade_timestamp à la milliseconde). Pas de TimescaleDB installé sur cette
-- instance self-hosted (vérifié : pg_extension ne liste que plpgsql,
-- uuid-ossp, pgcrypto, pg_net, pg_stat_statements, supabase_vault, vector) —
-- bucketing écrit en SQL standard.
--
-- Deux problèmes DISTINCTS, deux fonctions :
--   1) get_intraday_candles      : bucket TEMPOREL (minute/heure) — group by
--      intervalle de temps fixe.
--   2) get_intraday_tick_candles : bucket par COMPTEUR de trades (1T/10T/...)
--      — regroupe N transactions consécutives, rien à voir avec le temps.
--
-- Sécurité : EXECUTE réservé à service_role, même pattern que
-- rebuild_positions (20260717070000) — l'API a déjà validé le palier
-- d'abonnement (require_feature) avant d'appeler ces RPC, jamais d'accès
-- direct anon/authenticated (cohérent avec le durcissement intraday de
-- 20260712160000_deny_anon_intraday_daily.sql).

CREATE OR REPLACE FUNCTION public.get_intraday_candles(
  p_instrument_id uuid,
  p_market_date date,
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
    AND market_date = p_market_date
  GROUP BY 1
  ORDER BY 1;
$$;

CREATE OR REPLACE FUNCTION public.get_intraday_tick_candles(
  p_instrument_id uuid,
  p_market_date date,
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
      AND market_date = p_market_date
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

REVOKE ALL ON FUNCTION public.get_intraday_candles(uuid, date, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_intraday_candles(uuid, date, int) TO service_role;

REVOKE ALL ON FUNCTION public.get_intraday_tick_candles(uuid, date, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_intraday_tick_candles(uuid, date, int) TO service_role;

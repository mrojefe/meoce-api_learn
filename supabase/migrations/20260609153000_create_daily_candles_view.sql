-- Création de la Vue SQL pour fusionner daily_candles et daily_volume
CREATE OR REPLACE VIEW public.daily_candles_with_volume AS
SELECT
  c.instrument_id,
  c.date,
  c.open_price,
  c.high_price,
  c.low_price,
  c.close_price,
  c.previous_close,
  c.change_percent,
  c.created_at,
  c.updated_at,
  COALESCE(v.quantity, 0) AS volume,
  COALESCE(v.value, 0) AS value_traded,
  COALESCE(v.trade_count, 0) AS trade_count
FROM public.daily_candles c
LEFT JOIN public.daily_volume v
  ON c.instrument_id = v.instrument_id AND c.date = v.date;

-- Permissions
GRANT SELECT ON public.daily_candles_with_volume TO anon, authenticated, service_role;

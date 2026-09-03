-- Volume obligations absent du graphe (2026-08-12, JF — "tu prends le volume où ?
-- on prend nos volumes de BFIN"). Ma tentative précédente (worker_obligations_cotation.py,
-- extraction raw_col_7/8 du PDF BOC → bond_candles.volume_titre/volume_valeur) était
-- la MAUVAISE approche : `daily_volume` (alimentée par worker_trade.py, source BFIN
-- prioritaire, BOC en renfort — cf. worker_trade.py:343-379 "bfin gagne toujours")
-- couvre DÉJÀ les obligations (18 721 lignes bond + 247 sukuk, vérifié en base,
-- données fraîches jusqu'à 2026-08-10). C'est la même source déjà utilisée pour les
-- actions via `daily_candles_with_volume` (20260609153000/20260611120000) — même
-- pattern, simplement répliqué ici pour bond_candles.
CREATE OR REPLACE VIEW public.bond_candles_with_volume
WITH (security_invoker = true)
AS
SELECT
  bc.instrument_id,
  bc.date,
  bc.close_price,
  bc.coupon_couru,
  bc.coupon_montant,
  bc.status_cotation,
  bc.source,
  bc.boc_format_model,
  bc.created_at,
  bc.updated_at,
  COALESCE(v.quantity, 0::bigint)  AS volume,
  COALESCE(v.value,    0::numeric) AS value_traded,
  COALESCE(v.trade_count, 0)       AS trade_count
FROM public.bond_candles bc
LEFT JOIN public.daily_volume v
  ON bc.instrument_id = v.instrument_id
 AND bc.date = v.date;

GRANT SELECT ON public.bond_candles_with_volume TO anon, authenticated;

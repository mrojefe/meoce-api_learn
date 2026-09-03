-- Vue consolidée `intraday_volume` : les 3 grandeurs de volume du JOUR EN COURS regroupées
-- par (instrument, date), au lieu d'aller les chercher dans des tables séparées à chaque
-- appel de la bougie live (_compute_live_candle tapait intraday_snapshots PUIS
-- intraday_transactions séparément). Une seule source, un seul appel, la logique au même endroit.
--
--   quantity_cumul / value_cumul  ← dernier intraday_snapshots du jour (cumuls)
--   trade_count                   ← COUNT(intraday_transactions) du jour
--   + last_trade_price/high/low/scraped_at (déjà nécessaires à la bougie live)
--
-- Filtrable efficacement (chemin CHAUD, bougie live pollée ~30 s) : les prédicats
-- WHERE instrument_id=… [AND market_date=…] se poussent dans les deux sous-requêtes,
-- servies par idx_intraday_snap_instr_date_scraped et idx_tx_instr_date.
--
-- SÉCURITÉ / MOAT : les tables intraday_* ont le SELECT anon RÉVOQUÉ (anti-scraping, WS-B).
-- Une vue s'exécute par défaut avec les droits de son PROPRIÉTAIRE → elle contournerait ce
-- REVOKE. On la crée donc en security_invoker=true (PG15+) : elle respecte les droits de
-- l'APPELANT → anon reste bloqué, service_role (get_admin_db, BYPASSRLS) passe. On révoque
-- aussi explicitement anon/authenticated par ceinture-bretelles.
--
-- Idempotent (CREATE OR REPLACE + REVOKE/GRANT rejouables). Aucune donnée touchée (objet DDL).

CREATE OR REPLACE VIEW public.intraday_volume
  WITH (security_invoker = true) AS
SELECT
  s.instrument_id,
  s.market_date,
  s.scraped_at,
  s.last_trade_price,
  s.high_price,
  s.low_price,
  s.quantity_cumul,
  s.value_cumul,
  COALESCE(t.trade_count, 0) AS trade_count
FROM (
  SELECT DISTINCT ON (instrument_id, market_date)
    instrument_id, market_date, scraped_at, last_trade_price,
    high_price, low_price, quantity_cumul, value_cumul
  FROM public.intraday_snapshots
  ORDER BY instrument_id, market_date, scraped_at DESC
) s
LEFT JOIN (
  SELECT instrument_id, market_date, COUNT(*)::int AS trade_count
  FROM public.intraday_transactions
  GROUP BY instrument_id, market_date
) t ON t.instrument_id = s.instrument_id AND t.market_date = s.market_date;

REVOKE ALL ON public.intraday_volume FROM anon, authenticated;
GRANT SELECT ON public.intraday_volume TO service_role;

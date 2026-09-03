-- Supprime les bougies fantômes créées par le backfill historique SikaFinance
-- (source DS-SK6/DS-SK6R) sur des jours fériés BRVM officiels où aucune séance
-- n'a eu lieu (calendrier de cotation BRVM 2026, confirmé par 10 sources
-- indépendantes : BFIN, BOC x3 miroirs, intraday SGI/AGI, Richbourse, registre
-- boc_manquants_2000_2026.csv).
--
-- Jours fériés concernés :
--   2026-05-01 : Fête du Travail
--   2026-05-14 : Ascension
--   2026-05-25 : Lundi de Pentecôte
--   2026-05-27 : Tabaski
--
-- Ces lignes portaient un prix (report du cours de la veille) mais aucun
-- volume, faussant l'affichage frontend d'un jour où le marché était fermé.

DELETE FROM public.daily_candles
WHERE date IN ('2026-05-01', '2026-05-14', '2026-05-25', '2026-05-27');

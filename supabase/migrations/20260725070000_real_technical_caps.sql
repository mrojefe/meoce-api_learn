-- ============================================================================
-- Règle produit (JF) : ne JAMAIS afficher « illimité » — toujours un MAX chiffré.
--
-- Ces 4 clés reçoivent des valeurs DÉRIVÉES DE LA RÉALITÉ TECHNIQUE de la base
-- (pas des choix business inventés) :
--   • history_years_max / history_years_default = 27
--     → la bougie DAILY la plus ancienne en base date du 1998-09-16 (27 ans).
--       Poser 27 ne retire aucun droit réel : c'est déjà toute la profondeur
--       disponible.
--   • live_history_days = 89
--     → le point intraday le plus ancien en base date d'il y a 89 jours.
--   • max_flags (Pro) = 7
--     → la palette de couleurs de fanions est un tableau FIXE de 7 couleurs
--       (hooks/useWatchlistFlags.ts, FLAG_COLORS) : un 8e serait sans effet,
--       l'UI ne propose pas plus.
--
-- Les autres clés encore à null (max_watchlists, max_screener_saves,
-- max_virtual_portfolios, max_indicators_on_chart, max_news_bookmarks plus)
-- n'ont AUCUN plafond technique dérivable : ce sont des décisions produit,
-- volontairement laissées de côté ici (demandées séparément à JF).
-- ============================================================================

UPDATE subscription_plans
   SET features = features
       || jsonb_build_object('history_years_max', 27)
       || jsonb_build_object('history_years_default', 27)
       || jsonb_build_object('live_history_days', 89)
 WHERE code IN ('plus', 'pro');

UPDATE subscription_plans
   SET features = features || jsonb_build_object('max_flags', 7)
 WHERE code = 'pro';

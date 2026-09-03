-- Nouvelle clé de catalogue : accès aux timeframes intraday granulaires
-- (tick/minute/heure) construits en direct depuis intraday_transactions.
-- Réservé au palier le plus élevé (pro), pas une simple fonctionnalité
-- premium cosmétique — gating serveur via require_feature() (voir migration
-- suivante pour les RPC d'agrégation).
INSERT INTO public.features (key, label, description, kind, free_default, anon_default, category, display_order)
VALUES (
  'intraday_granular_timeframes', 'Intervalles intraday granulaires',
  'Accès aux bougies tick/minute/heure construites en direct depuis les transactions individuelles (réservé au palier le plus élevé)',
  'boolean', 'false', 'false', 'data', 210
)
ON CONFLICT (key) DO NOTHING;

-- 'free' et 'plus' héritent de free_default=false via get_user_entitlements()
-- tant que la clé n'apparaît pas dans leur jsonb `features` (comportement déjà
-- en place ailleurs, cf. 20260712170000_feature_chart_types_flags.sql). On
-- ajoute donc UNIQUEMENT aux plans du plus haut palier — 'pro' (actif) et
-- 'premium' (masqué mais toujours souscrit par 3 comptes migrés, cf.
-- 20260724100000_pricing_tiers_plus_pro.sql — ne pas les priver de ce qu'ils
-- avaient implicitement en tant que palier historique le plus élevé).
UPDATE public.subscription_plans
   SET features = features || jsonb_build_object('intraday_granular_timeframes', true)
 WHERE code IN ('pro', 'premium')
   AND NOT (features ? 'intraday_granular_timeframes');

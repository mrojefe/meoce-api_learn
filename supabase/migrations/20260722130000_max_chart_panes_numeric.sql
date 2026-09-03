-- ============================================================================
-- multi_layout (booléen) -> max_chart_panes (limite numérique)
--
-- Audit plans custom 2026-07-22 : "1 2 3 et ceux qui viendront dans le futur"
-- — un booléen ne peut exprimer QUE "tout ou rien" (multi-graphes débloqué ou
-- pas), impossible de dire "ce plan a droit à 2 panneaux max, cet autre à 3".
-- Renommé (pas juste retypé) : même piège que max_flags/DrawingToolbar — un
-- nom générique réutilisé avec un sens différent ailleurs serait retrouvé un
-- jour avec la mauvaise sémantique.
--
-- Mapping : gratuit = 1 (vue unique seulement), pro = illimité (null).
-- ============================================================================

INSERT INTO features (key, label, description, kind, free_default, anon_default, category, display_order)
VALUES (
  'max_chart_panes',
  'Panneaux de graphique simultanés',
  'Nombre de panneaux affichables en même temps (1 = vue unique, null = illimité)',
  'limit',
  '1'::jsonb,
  '1'::jsonb,
  'chart',
  25
)
ON CONFLICT (key) DO NOTHING;

-- Le plan premium existant avait multi_layout=true (illimité) -> max_chart_panes=null.
UPDATE subscription_plans
   SET features = features || jsonb_build_object('max_chart_panes', null)
 WHERE code = 'premium' AND NOT (features ? 'max_chart_panes');

UPDATE subscription_plans
   SET features = features || jsonb_build_object('max_chart_panes', 1)
 WHERE code = 'free' AND NOT (features ? 'max_chart_panes');

-- Désactive l'ancienne clé (gardée en base pour ne rien casser rétroactivement
-- si un octroi user_features existant la référence encore, mais ne doit plus
-- être lue par le nouveau code frontend).
UPDATE features SET is_active = false WHERE key = 'multi_layout';

-- ============================================================================
-- max_news_bookmarks — limite du nombre total d'articles signés/signables
--
-- Audit plans custom 2026-07-22 : les signets news (user_news_bookmarks,
-- migration 20260721193000) n'avaient AUCUNE limite — n'importe qui pouvait
-- signer un nombre illimité d'articles. Ajoute la clé d'entitlement, comme
-- les autres compteurs de la table `features` (ajustable sans déploiement).
--
-- Défaut choisi : gratuit = 15 (généreux, feature à faible coût), pro =
-- illimité. Valeur ajustable en base à tout moment (UPDATE features SET
-- free_default=... WHERE key='max_news_bookmarks').
-- ============================================================================

INSERT INTO features (key, label, description, kind, free_default, anon_default, category, display_order)
VALUES (
  'max_news_bookmarks',
  'Signets d''articles',
  'Nombre total d''articles signés simultanément (null = illimité)',
  'limit',
  '15'::jsonb,
  '15'::jsonb,
  'news',
  120
)
ON CONFLICT (key) DO NOTHING;

UPDATE subscription_plans
   SET features = features || jsonb_build_object('max_news_bookmarks', null)
 WHERE code = 'premium' AND NOT (features ? 'max_news_bookmarks');

UPDATE subscription_plans
   SET features = features || jsonb_build_object('max_news_bookmarks', 15)
 WHERE code = 'free' AND NOT (features ? 'max_news_bookmarks');

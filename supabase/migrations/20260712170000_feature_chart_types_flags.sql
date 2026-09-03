-- ⚠️ MIGRATION RECONSTITUÉE (2026-07-25) — le fichier d'origine n'a JAMAIS été
-- commité : la migration avait été appliquée directement en production et
-- `schema_migrations` la référençait sans qu'aucun fichier n'existe. L'audit du
-- 2026-07-25 a relevé 15 versions dans ce cas — une reconstruction de la base
-- depuis les migrations aurait produit un schéma DIFFÉRENT de la production.
--
-- Contenu déduit du schéma RÉEL en production, pas du texte d'origine. Écrit de
-- façon IDEMPOTENTE : sans effet sur la prod (version déjà enregistrée), correct
-- sur une base reconstruite de zéro.

INSERT INTO public.features (key, label, description, kind, free_default, anon_default, category, display_order)
VALUES
  ('max_flags', 'Flags / marqueurs',
   'Nombre de flags (arrow-up/down) par symbole (null = illimité)',
   'limit', '1', '1', 'chart', 46),
  ('custom_timeframes', 'Intervalles personnalisés',
   NULL, 'boolean', 'false', 'false', 'ui', 50)
ON CONFLICT (key) DO NOTHING;

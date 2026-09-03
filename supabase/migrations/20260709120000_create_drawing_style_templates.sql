-- ⚠️ MIGRATION RECONSTITUÉE (2026-07-25) — le fichier d'origine n'a JAMAIS été
-- commité : la migration avait été appliquée directement en production et
-- `schema_migrations` la référençait sans qu'aucun fichier n'existe. L'audit du
-- 2026-07-25 a relevé 15 versions dans ce cas — une reconstruction de la base
-- depuis les migrations aurait produit un schéma DIFFÉRENT de la production.
--
-- Contenu déduit du schéma RÉEL en production, pas du texte d'origine. Écrit de
-- façon IDEMPOTENTE : sans effet sur la prod (version déjà enregistrée), correct
-- sur une base reconstruite de zéro.

-- La table `drawing_style_templates` N'EXISTE PAS en production : la version a
-- été enregistrée mais son objet abandonné depuis (les styles de dessin vivent
-- finalement dans `chart_templates` / `user_drawings`). Rien à recréer — ce
-- fichier documente une version consommée, sans effet résiduel.
SELECT 1;

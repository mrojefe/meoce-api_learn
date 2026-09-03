-- ⚠️ MIGRATION RECONSTITUÉE (2026-07-25) — le fichier d'origine n'a JAMAIS été
-- commité : la migration avait été appliquée directement en production et
-- `schema_migrations` la référençait sans qu'aucun fichier n'existe. L'audit du
-- 2026-07-25 a relevé 15 versions dans ce cas — une reconstruction de la base
-- depuis les migrations aurait produit un schéma DIFFÉRENT de la production.
--
-- Contenu déduit du schéma RÉEL en production, pas du texte d'origine. Écrit de
-- façon IDEMPOTENTE : sans effet sur la prod (version déjà enregistrée), correct
-- sur une base reconstruite de zéro.

-- Colonnes ajoutées à chart_templates pour l'autosave de session et l'UT.
ALTER TABLE public.chart_templates ADD COLUMN IF NOT EXISTS timeframe   text;
ALTER TABLE public.chart_templates ADD COLUMN IF NOT EXISTS is_autosave boolean NOT NULL DEFAULT false;

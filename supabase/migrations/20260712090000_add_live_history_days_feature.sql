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
VALUES ('live_history_days', 'Profondeur intraday (jours)',
        'Jours de bourse d''historique intraday visibles en arrière (null = illimité).',
        'limit', '5', '5', 'data', 15)
ON CONFLICT (key) DO NOTHING;

-- Drop des tables de customisation ORPHELINES.
--
-- Contexte : screener_templates, indicator_preferences et drawing_style_templates
-- ont été créées par le schéma initial (20260517130240) mais n'ont JAMAIS été
-- câblées : aucun code (frontend ni API) ne les lit/écrit, 0 ligne en base,
-- aucune FK entrante, aucune vue/fonction dépendante. Décision utilisateur : drop.
-- (Les préférences d'indicateurs sont déjà couvertes par chart_templates.)
--
-- Sûr : DROP TABLE retire aussi automatiquement leurs policies RLS. Pas de CASCADE
-- (aucun objet dépendant vérifié). Idempotent via IF EXISTS. Backup pris avant
-- application (orphan_tables_backup.sql) pour réversibilité.

DROP TABLE IF EXISTS public.screener_templates;
DROP TABLE IF EXISTS public.indicator_preferences;
DROP TABLE IF EXISTS public.drawing_style_templates;

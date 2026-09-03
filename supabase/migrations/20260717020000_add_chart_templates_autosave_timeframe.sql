-- RATTRAPAGE DE DÉRIVE Git ↔ base (aucun changement fonctionnel attendu en prod).
--
-- Constat de l'audit, vérifié en base : `chart_templates.is_autosave`,
-- `chart_templates.timeframe` et l'index unique partiel `uq_chart_templates_autosave`
-- EXISTENT en production, mais aucune migration ne les crée — `initial_schema.sql`
-- définit `chart_templates` SANS ces trois objets, et
-- `grep -rn "is_autosave" supabase/migrations/` ne renvoyait rien.
-- Conséquence : sur une base reconstruite depuis les migrations, la route
-- /api/user/chart-templates (qui écrit is_autosave et timeframe) échouait.
--
-- Cette migration DÉCLARE l'existant, à l'identique de ce qui a été relevé par \d.
-- Strictement IDEMPOTENTE, NO-OP attendu sur la prod actuelle, aucun DML.

ALTER TABLE public.chart_templates
  ADD COLUMN IF NOT EXISTS timeframe text;

ALTER TABLE public.chart_templates
  ADD COLUMN IF NOT EXISTS is_autosave boolean NOT NULL DEFAULT false;

-- Index UNIQUE PARTIEL : garantit UNE SEULE ligne d'autosave par utilisateur, tout en
-- laissant un nombre libre de modèles nommés (is_autosave = false non couvert par la
-- clause WHERE). C'est ce qui rend possible un vrai upsert sur l'autosave — la route
-- fait aujourd'hui un DELETE puis un INSERT non atomique (course entre deux onglets),
-- corrigé séparément.
CREATE UNIQUE INDEX IF NOT EXISTS uq_chart_templates_autosave
  ON public.chart_templates USING btree (user_id)
  WHERE is_autosave;

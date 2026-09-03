-- Renomme daily_market_summary -> market_summary et ajoute la colonne
-- `period` (daily|weekly) pour distinguer les résumés quotidiens des
-- récaps hebdomadaires (nouveau, samedi 01h00 UTC). Déjà appliqué en
-- prod directement (docker exec psql) le 2026-07-18 — ce fichier
-- documente le changement pour la traçabilité et les futurs environnements.

ALTER TABLE public.daily_market_summary RENAME TO market_summary;

ALTER TABLE public.market_summary
  ADD COLUMN period text NOT NULL DEFAULT 'daily'
  CHECK (period IN ('daily', 'weekly'));

ALTER TABLE public.market_summary DROP CONSTRAINT daily_market_summary_date_key;
ALTER TABLE public.market_summary
  ADD CONSTRAINT market_summary_date_period_key UNIQUE (date, period);

ALTER TABLE public.market_summary
  RENAME CONSTRAINT daily_market_summary_pkey TO market_summary_pkey;
ALTER INDEX IF EXISTS daily_market_summary_date_idx RENAME TO market_summary_date_idx;

DROP POLICY IF EXISTS "public read daily_market_summary" ON public.market_summary;
CREATE POLICY "public read market_summary" ON public.market_summary FOR SELECT USING (true);

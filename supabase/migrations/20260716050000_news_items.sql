-- Référentiel des news financières réelles (remplace les mocks MOCK_NEWS de
-- l'accueil et de NewsPanel.tsx, cf. chantier "vraies news" 2026-07-16).
-- Source #1 : Sikafinance (/marches/actualites_bourse_brvm), scraper isolé
-- (voir meoce-airflow/dags/workers/worker_news_sikafinance.py à venir).
-- Dédup via (source, source_id) — l'id numérique en fin d'URL Sikafinance
-- (ex. ..._63013) est stable et unique par article.
-- Idempotent.

CREATE TABLE IF NOT EXISTS public.news_items (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source        TEXT NOT NULL,               -- 'sikafinance', 'brvm_officiel', ...
  source_id     TEXT NOT NULL,               -- id stable côté source (dédup)
  url           TEXT NOT NULL,
  title         TEXT NOT NULL,
  summary       TEXT,
  image_url     TEXT,
  published_at  TIMESTAMPTZ NOT NULL,
  scraped_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source, source_id)
);

CREATE INDEX IF NOT EXISTS idx_news_items_published_at ON public.news_items(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_news_items_source ON public.news_items(source);

ALTER TABLE public.news_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS read_all ON public.news_items;
CREATE POLICY read_all ON public.news_items FOR SELECT USING (true);
GRANT SELECT ON public.news_items TO anon, authenticated;

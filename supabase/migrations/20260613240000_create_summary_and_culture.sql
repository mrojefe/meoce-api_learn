-- Résumé de marché quotidien (généré par Gemini après clôture BOC)
CREATE TABLE IF NOT EXISTS daily_market_summary (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  date          date NOT NULL UNIQUE,
  bullets       jsonb NOT NULL DEFAULT '[]', -- [{color, text}]
  body          text NOT NULL DEFAULT '',
  source        text NOT NULL DEFAULT 'ai', -- 'ai' | 'manual'
  boc_date      text,                        -- référence BOC ayant servi de base
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS daily_market_summary_date_idx ON daily_market_summary(date DESC);

-- Items culturels (conte d'Afrique / c'est-quoi-ça)
-- Alimenté par import Gemini (3399 items depuis DATA/BRONZE/03_PIPELINE_GEMINI/output/)
CREATE TABLE IF NOT EXISTS culture_items (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  categorie       text NOT NULL,           -- 'conte' | 'ckoissa' | 'proverbe' | ...
  tag             text NOT NULL,           -- 'Proverbe' | 'Définition' | 'Concept' | 'Histoire' | ...
  texte           text NOT NULL,
  source_url      text,
  source_domaine  text,                    -- brvm.org | afribourse.com | ...
  date_publication date,
  score_bourse    integer,                 -- 0-10 (pertinence marché boursier)
  entites         text[],                  -- noms propres extraits par Gemini
  actif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS culture_items_categorie_idx ON culture_items(categorie);
CREATE INDEX IF NOT EXISTS culture_items_actif_idx ON culture_items(actif) WHERE actif = true;

-- RLS : lecture publique pour les deux tables
ALTER TABLE daily_market_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE culture_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public read daily_market_summary"
  ON daily_market_summary FOR SELECT USING (true);

CREATE POLICY "public read culture_items"
  ON culture_items FOR SELECT USING (actif = true);

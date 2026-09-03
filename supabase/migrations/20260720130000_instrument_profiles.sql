-- Zone 4 Fondamentaux (partielle) — identité d'entreprise, distincte des
-- tables marché déjà existantes (corporate_actions, dividends — vides à ce
-- jour, alimentées séparément). Import initial : richbourse.com (47 sociétés
-- BRVM), source figée, voir script d'import.

CREATE TABLE IF NOT EXISTS instrument_profiles (
  instrument_id       UUID        PRIMARY KEY REFERENCES instruments(id) ON DELETE CASCADE,
  presentation        TEXT,
  sector_determinants TEXT,
  phone               TEXT,
  website              TEXT,
  listing_date        DATE,
  float_pct           NUMERIC(5,2),
  shares_outstanding  BIGINT,
  source              TEXT        NOT NULL DEFAULT 'richbourse',
  source_url          TEXT,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_instrument_profiles_updated_at
  BEFORE UPDATE ON instrument_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE instrument_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY instrument_profiles_read_all ON instrument_profiles FOR SELECT USING (true);

-- Actionnariat — table séparée (pas de JSON imbriqué) : l'actionnariat change
-- dans le temps, `source`/`as_of_date` permettent d'ajouter des snapshots
-- ultérieurs (autre source, autre date) sans écraser l'historique.
CREATE TABLE IF NOT EXISTS instrument_shareholders (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  instrument_id  UUID        NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  name           TEXT        NOT NULL,
  pct            NUMERIC(5,2),
  source         TEXT        NOT NULL DEFAULT 'richbourse',
  as_of_date     DATE        NOT NULL DEFAULT CURRENT_DATE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (instrument_id, name, source, as_of_date)
);

CREATE INDEX IF NOT EXISTS idx_instrument_shareholders_instrument ON instrument_shareholders(instrument_id);

ALTER TABLE instrument_shareholders ENABLE ROW LEVEL SECURITY;
CREATE POLICY instrument_shareholders_read_all ON instrument_shareholders FOR SELECT USING (true);

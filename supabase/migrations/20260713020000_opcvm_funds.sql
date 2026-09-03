-- Fonds OPCVM BRVM — référentiel public (read-only), affichés dans le
-- Classement à côté des portefeuilles (toggle "Inclure les OPCVM", activé par
-- défaut côté frontend). Un OPCVM n'est PAS un portefeuille avec achats/ventes
-- (contrairement à bridge_recommendations) : sa VL (valeur liquidative) EST
-- son propre cours, donc un historique de valeur directe, pas des positions.
-- Idempotent.

-- ── 1. Référentiel des fonds (catégorie STABLE = vote majoritaire sur 12
--       mois glissants, pas la valeur brute du jour qui peut être bruitée
--       côté BRVM elle-même — cf. mémoire opcvm_fonds_reguliers_20260713) ──
CREATE TABLE IF NOT EXISTS public.opcvm_funds (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nom_opcvm        TEXT NOT NULL UNIQUE,
  societe_gestion  TEXT,
  categorie_stable TEXT,              -- D/A/OMLT/OCT/M/OPCR (vote majoritaire 12m)
  frequence        TEXT NOT NULL DEFAULT 'QUOTIDIENNES'
                        CHECK (frequence IN ('QUOTIDIENNES', 'HEBDOMADAIRES', 'MENSUELLES')),
  first_vl_date    DATE,
  last_vl_date     DATE,
  is_active        BOOLEAN NOT NULL DEFAULT true,  -- false = isolé (plus publié récemment)
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_opcvm_funds_active ON public.opcvm_funds(is_active);

CREATE OR REPLACE FUNCTION update_updated_at_opcvm_funds()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_opcvm_funds_updated_at ON public.opcvm_funds;
CREATE TRIGGER trg_opcvm_funds_updated_at
  BEFORE UPDATE ON public.opcvm_funds
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_opcvm_funds();

ALTER TABLE public.opcvm_funds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS read_all ON public.opcvm_funds;
CREATE POLICY read_all ON public.opcvm_funds FOR SELECT USING (true);
GRANT SELECT ON public.opcvm_funds TO anon, authenticated;

-- ── 2. Historique de VL — équivalent direct de portfolio_snapshots, mais la
--       "valeur" ici est directement la VL du fonds, pas une valorisation de
--       positions. cumulative_return calculé depuis la première VL connue.
CREATE TABLE IF NOT EXISTS public.opcvm_nav_history (
  fund_id            UUID NOT NULL REFERENCES public.opcvm_funds(id) ON DELETE CASCADE,
  date               DATE NOT NULL,
  vl                 NUMERIC(18,4) NOT NULL,
  daily_return       NUMERIC(10,6),
  cumulative_return  NUMERIC(10,6),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (fund_id, date)
);
CREATE INDEX IF NOT EXISTS idx_opcvm_nav_fund_date ON public.opcvm_nav_history(fund_id, date);

ALTER TABLE public.opcvm_nav_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS read_all ON public.opcvm_nav_history;
CREATE POLICY read_all ON public.opcvm_nav_history FOR SELECT USING (true);
GRANT SELECT ON public.opcvm_nav_history TO anon, authenticated;

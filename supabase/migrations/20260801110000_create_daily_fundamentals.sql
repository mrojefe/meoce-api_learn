-- Table d'accueil des ratios fondamentaux quotidiens : PER et rendement net
-- du dividende (tâche #68).
--
-- CONTEXTE — 02_SILVER/ACTION/SILVER_ACTION_FONDAMENTAUX.csv (PIPELINE_BRVM)
-- contient 118 293 valeurs de PER et 111 891 de Rdt.net, par symbole et par
-- séance, depuis 2002. Aucune table Supabase ne pouvait les recevoir.
--
-- DÉCISION DE CONCEPTION — table dédiée plutôt que colonnes ajoutées à
-- `daily_candles`. Raisons :
--   1. `daily_candles` est une table de PRIX (OHLC) dont les 4 colonnes de
--      cours sont NOT NULL et gardées par 2 CHECK d'ordre (high>=low, etc.).
--      Les ratios sont des DÉRIVÉS de valorisation (cours / résultat par
--      action), pas des faits de cotation : les mélanger casse la cohérence
--      sémantique de la table.
--   2. `daily_candles` est écrite par plusieurs pipelines (source
--      'sikafinance', 'richbourse', BOC) avec des upserts qui listent leurs
--      colonnes ; ajouter des colonnes éparses exposerait le PER à être
--      écrasé/remis à NULL par le premier import qui ré-upserte la ligne
--      complète sans les connaître. Risque d'effet de bord non maîtrisable.
--   3. Les couvertures diffèrent : 167 313 lignes dans daily_candles contre
--      187 843 lignes-séances côté fondamentaux BOC — les deux ensembles ne
--      se recouvrent pas, des lignes de PER n'auraient aucune ligne OHLC où
--      atterrir (et l'inverse), ce qui obligerait soit à perdre de la donnée
--      soit à créer des lignes OHLC fictives — inacceptable.
--   4. La table dédiée reste extensible (payout, BPA, capi, EV/EBITDA…) sans
--      re-toucher la table la plus lue de la base.
-- Le join se fait sur (instrument_id, date), clé identique à daily_candles.
--
-- VALEURS — aucune valeur devinée ni imputée : les sentinelles de la source
-- ('-', 'ND', et quelques cellules d'extraction corrompues type '3,74%')
-- deviennent NULL. Pas de CHECK de bornes sur `per` : un PER négatif est
-- légitime (société en perte) et un PER élevé aussi (BNBC dépasse 1 000 en
-- mai 2025 dans la source) — contraindre reviendrait à inventer une règle
-- métier. `dividend_yield_net` est exprimé en POURCENTAGE (ex : 7.83 = 7,83 %),
-- comme dans le BOC.

CREATE TABLE IF NOT EXISTS public.daily_fundamentals (
  instrument_id       uuid        NOT NULL REFERENCES public.instruments(id) ON DELETE CASCADE,
  date                date        NOT NULL,
  per                 numeric(18,4),
  dividend_yield_net  numeric(18,4),
  source              text        NOT NULL DEFAULT 'boc_pdf',
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT daily_fundamentals_pkey PRIMARY KEY (instrument_id, date)
);

CREATE INDEX IF NOT EXISTS idx_daily_fundamentals_date
  ON public.daily_fundamentals (date DESC);

DROP TRIGGER IF EXISTS trg_daily_fundamentals_updated_at ON public.daily_fundamentals;
CREATE TRIGGER trg_daily_fundamentals_updated_at
  BEFORE UPDATE ON public.daily_fundamentals
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.daily_fundamentals ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'daily_fundamentals' AND policyname = 'read_all'
  ) THEN
    CREATE POLICY read_all ON public.daily_fundamentals FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'daily_fundamentals' AND policyname = 'service_role_full_access'
  ) THEN
    CREATE POLICY service_role_full_access ON public.daily_fundamentals
      TO service_role USING (true) WITH CHECK (true);
  END IF;
END $$;

GRANT SELECT ON public.daily_fundamentals TO anon, authenticated;

COMMENT ON TABLE public.daily_fundamentals IS
  'Ratios fondamentaux par séance (PER, rendement net). Origine : PIPELINE_BRVM 02_SILVER/ACTION/SILVER_ACTION_FONDAMENTAUX.csv (BOC PDF). Séparée de daily_candles : donnée dérivée de valorisation, pas de cotation.';
COMMENT ON COLUMN public.daily_fundamentals.dividend_yield_net IS
  'Rendement net du dividende en POURCENTAGE (7.83 = 7,83 %), tel que publié au BOC.';

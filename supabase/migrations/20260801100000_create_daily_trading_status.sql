-- Table canonique du STATUT DE COTATION par séance (tâche #59).
--
-- CONTEXTE — le statut de cotation était éclaté sur 3 tables, chacune ne
-- couvrant qu'un type d'instrument, et jamais complètement alimentée :
--   * bond_candles.status_cotation      (obligations)
--   * right_candles.trading_status      (droits, 88/353 renseignés)
--   * daily_order_book.trading_status   (72,6 % NULL — jamais propagé)
-- Aucune de ces colonnes ne permet de répondre à « quel était le statut de
-- l'instrument X le jour D » de façon uniforme. Le lake PIPELINE_BRVM produit
-- déjà le rapprochement des 3 types dans 03_GOLD/GOLD_STATUS_COTATION.csv
-- (482 634 lignes, ACTION + OBLIGATION + DROIT), mais son script de build
-- (`gold_build_status_cotation.py`) documente explicitement qu'il n'écrit
-- rien en base et que « la table STATUS finale est un chantier distinct ».
-- C'est cette table-là.
--
-- NOMMAGE — aligné sur les conventions déjà en place pour les séries
-- quotidiennes de marché : `daily_candles`, `daily_order_book`,
-- `daily_volume` → `daily_trading_status`, clé (instrument_id, date) et
-- colonne `date` comme dans `daily_candles`/`right_candles`. Volontairement
-- PAS `instrument_status_history` : `instruments.status` désigne déjà le
-- statut de CYCLE DE VIE (active/delisted/suspended/pending_listing) et un
-- nom en `instrument_status_*` prêterait à confusion avec l'historique de
-- CE statut-là, qui est un tout autre concept.
--
-- DOMAINE DE `status` — les 4 valeurs observées dans GOLD_STATUS_COTATION.csv
-- (comptage réel, aucune valeur devinée) :
--     NC     313 094  (non coté ce jour-là)
--     <vide> 153 674  (aucun marqueur au BOC = instrument coté normalement)
--     SP      15 396  (suspendu)
--     DIF        470  (différé)
-- Le marqueur vide est encodé explicitement 'COTE' plutôt que NULL : une
-- table de statut où « pas de statut » veut dire « coté » serait piégeuse
-- (NULL = inconnu partout ailleurs dans ce schéma). Cette lecture du vide
-- n'est pas une supposition, elle est corroborée par le prix : 146 684 des
-- 153 674 lignes vides (95,5 %) portent un close_price, alors que NC/SP/DIF
-- sont quasi systématiquement sans prix (313 072/313 094 NC sans prix).
-- 'Marché' est admis en plus car c'est la valeur déjà utilisée pour le même
-- concept par les CHECK de `daily_order_book` et `right_candles` (source QR,
-- 3 754 lignes) : garder le même domaine évite une divergence de vocabulaire
-- le jour où l'on propagera ces lignes-là ici.

CREATE TABLE IF NOT EXISTS public.daily_trading_status (
  instrument_id uuid        NOT NULL REFERENCES public.instruments(id) ON DELETE CASCADE,
  date          date        NOT NULL,
  status        text        NOT NULL,
  close_price   numeric(18,4),
  source        text        NOT NULL DEFAULT 'boc_pdf',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT daily_trading_status_pkey PRIMARY KEY (instrument_id, date),
  CONSTRAINT daily_trading_status_status_check
    CHECK (status = ANY (ARRAY['COTE'::text, 'NC'::text, 'SP'::text, 'DIF'::text, 'Marché'::text]))
);

CREATE INDEX IF NOT EXISTS idx_daily_trading_status_date
  ON public.daily_trading_status (date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_trading_status_status
  ON public.daily_trading_status (status);

-- updated_at : même trigger partagé que daily_candles/right_candles/daily_order_book.
DROP TRIGGER IF EXISTS trg_daily_trading_status_updated_at ON public.daily_trading_status;
CREATE TRIGGER trg_daily_trading_status_updated_at
  BEFORE UPDATE ON public.daily_trading_status
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- RLS : lecture publique (donnée de marché, comme bond_candles/daily_candles),
-- aucune écriture pour anon/authenticated. Le GRANT est indispensable EN PLUS
-- de la policy (cf. 20260727090000 : RLS ne dispense pas du GRANT de base).
ALTER TABLE public.daily_trading_status ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'daily_trading_status' AND policyname = 'read_all'
  ) THEN
    CREATE POLICY read_all ON public.daily_trading_status FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'daily_trading_status' AND policyname = 'service_role_full_access'
  ) THEN
    CREATE POLICY service_role_full_access ON public.daily_trading_status
      TO service_role USING (true) WITH CHECK (true);
  END IF;
END $$;

GRANT SELECT ON public.daily_trading_status TO anon, authenticated;

COMMENT ON TABLE public.daily_trading_status IS
  'Source de vérité unique du statut de cotation par séance (ACTION+OBLIGATION+DROIT). Origine : PIPELINE_BRVM 03_GOLD/GOLD_STATUS_COTATION.csv (BOC PDF). COTE = aucun marqueur au BOC (instrument coté normalement).';
COMMENT ON COLUMN public.daily_trading_status.close_price IS
  'Cours de clôture de la séance tel que présent dans la source GOLD, conservé comme preuve/contrôle du statut (NC/SP/DIF sont quasi toujours sans prix). Ne remplace pas daily_candles/bond_candles.';

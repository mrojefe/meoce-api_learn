-- Migration: create daily_order_book
-- Carnet d'ordres résiduel journalier extrait du Bulletin Officiel de la Cote (BOC BRVM)
-- Un seul enregistrement par instrument × séance (meilleur bid/ask résiduel fin de journée)
-- Distinct de order_book_levels (carnet multi-niveaux temps réel du scraper live)

CREATE TABLE IF NOT EXISTS daily_order_book (
  -- Clé primaire : un seul enregistrement par instrument × séance
  instrument_id     uuid        NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  market_date       date        NOT NULL,

  -- Côté achat résiduel (meilleur prix acheteur)
  bid_price         numeric,
  bid_quantity      bigint,

  -- Côté vente résiduel (meilleur prix vendeur)
  ask_price         numeric,
  ask_quantity      bigint,

  -- Prix de référence de la séance (cours_reference BOC — absent de daily_candles)
  reference_price   numeric,

  -- Statut de cotation journalier (NC = non coté, SP = suspendu, DIF = différé)
  -- NULL = séance normale sans statut particulier
  trading_status    text
    CHECK (trading_status IS NULL OR trading_status IN ('NC', 'SP', 'DIF', 'Marché')),

  -- Traçabilité : lien vers le PDF source dans boc_documents
  -- Nullable : les données historiques (2009-2022) n'ont pas encore d'entrée dans boc_documents
  boc_document_id   uuid        REFERENCES boc_documents(id) ON DELETE SET NULL,

  -- Modèle Bronze d'extraction (M1…M7 & QR_ACTION_M2, etc.) — pour audit
  boc_format_model  text,

  -- Timestamps
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (instrument_id, market_date)
);

-- Index chronologique (requêtes "historique d'un instrument")
CREATE INDEX idx_daily_order_book_date_instr
  ON daily_order_book (market_date DESC, instrument_id);

-- Index FK boc_documents
CREATE INDEX idx_daily_order_book_boc_doc
  ON daily_order_book (boc_document_id)
  WHERE boc_document_id IS NOT NULL;

-- Trigger updated_at (même pattern que les autres tables du projet)
CREATE TRIGGER trg_daily_order_book_updated_at
  BEFORE UPDATE ON daily_order_book
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- ─── RLS ────────────────────────────────────────────────────────────────────
-- Les données BOC sont des données commerciales — aucun accès anonyme/public.
ALTER TABLE daily_order_book ENABLE ROW LEVEL SECURITY;

-- service_role : accès complet (pipeline d'ingestion, pas de restriction RLS)
CREATE POLICY "service_role_full_access" ON daily_order_book
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- authenticated : lecture uniquement pour les utilisateurs avec abonnement actif
-- Condition : abonnement actif (status = 'active') ET période non expirée
CREATE POLICY "subscribed_users_read" ON daily_order_book
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM subscriptions s
      WHERE s.user_id = auth.uid()
        AND s.status = 'active'
        AND (s.current_period_end IS NULL OR s.current_period_end > now())
    )
  );

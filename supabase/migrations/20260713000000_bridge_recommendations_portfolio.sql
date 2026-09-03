-- Portefeuille public "Bridge Recommandations" — suit mécaniquement les recos
-- hebdomadaires Bridge Securities (achat sur ++, jamais de vente). Structure
-- USER-DATA + référentiel uniquement (aucune donnée plateforme existante touchée).
-- Idempotent.

-- ── 1. Table des recommandations Bridge (référentiel public, read-only) ─────
CREATE TABLE IF NOT EXISTS public.bridge_recommendations (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  instrument_id UUID NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  symbol        TEXT NOT NULL,              -- dénormalisé pour traçabilité RAW
  reco_raw      TEXT NOT NULL CHECK (reco_raw IN ('++', '+', '-')),
  reco_score    SMALLINT NOT NULL CHECK (reco_score IN (-1, 0, 1)),
  date_from     DATE NOT NULL,
  date_to       DATE,
  source_file   TEXT,
  ingested_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (instrument_id, date_from)
);
CREATE INDEX IF NOT EXISTS idx_bridge_reco_date ON public.bridge_recommendations(date_from);

ALTER TABLE public.bridge_recommendations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS read_all ON public.bridge_recommendations;
CREATE POLICY read_all ON public.bridge_recommendations FOR SELECT USING (true);
GRANT SELECT ON public.bridge_recommendations TO anon, authenticated;

-- ── 2. Config plateforme (réutilise platform_config, rien de hardcodé) ──────
INSERT INTO platform_config (key, value) VALUES
  ('bridge_portfolio_entry_delay_trading_days', '0'::jsonb),
  ('bridge_portfolio_position_size_shares',     '1'::jsonb),
  ('bridge_portfolio_fee_rate_pct',             '1.0'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ── 3. Étendre le CHECK source pour distinguer ce portefeuille système ──────
ALTER TABLE portfolios DROP CONSTRAINT IF EXISTS portfolios_source_check;
ALTER TABLE portfolios ADD CONSTRAINT portfolios_source_check
  CHECK (source IN ('manual', 'pdf_import', 'bridge_reco'));

-- ── 4. Utilisateur système ("bot") propriétaire du portefeuille ─────────────
-- UUID fixe et mémorisable (facilite les jointures/scripts). Auth custom (pas
-- Supabase Auth) : la FK public.users(id)→auth.users a été supprimée en
-- 20260611161640 (« l'auth custom ne peuple pas auth.users »). Il n'y a donc
-- AUCUNE contrainte à satisfaire côté auth.users → l'ancien INSERT INTO auth.users
-- était mort (SEV-028) et a été retiré. Le bot vit uniquement dans public.users.
INSERT INTO public.users (id, username, email, display_name, status, role, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-00000000b0b1'::uuid,
  'bridge_securities_bot',
  'bridge-securities-bot@system.meoce.internal',
  'Bridge Securities — Suivi Recommandations',
  'active', 'api_client',
  now(), now()
)
ON CONFLICT (id) DO NOTHING;

-- ── 5. Le portefeuille public lui-même ───────────────────────────────────────
INSERT INTO portfolios (id, user_id, name, description, type, base_currency, source, is_public)
VALUES (
  '00000000-0000-0000-0000-00000000f0f1'::uuid,
  '00000000-0000-0000-0000-00000000b0b1'::uuid,
  'Bridge Securities — Suivi Recommandations',
  'Portefeuille simulé qui suit mécaniquement les recommandations d''achat (++) hebdomadaires de Bridge Securities. Achat uniquement, aucune vente. Voir platform_config pour les paramètres (délai d''exécution, taille de position, frais).',
  'virtual', 'XOF', 'bridge_reco', true
)
ON CONFLICT (id) DO NOTHING;

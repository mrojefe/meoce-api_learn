-- ZONE 13bis — Entitlements à-la-carte (additive ; ne touche pas subscription_plans/subscriptions)
-- Vision : pas de tiers figés. 1 user = un panier de features (à l'unité OU via package).
-- Réutilise le vocabulaire des clés jsonb déjà présentes dans subscription_plans.features.

-- 13bis.1 Catalogue atomique des features
CREATE TABLE IF NOT EXISTS features (
  key            TEXT PRIMARY KEY,
  label          TEXT NOT NULL,
  description    TEXT,
  kind           TEXT NOT NULL CHECK (kind IN ('boolean','limit')),
  free_default   JSONB NOT NULL DEFAULT 'false'::jsonb,  -- valeur incluse gratuitement (false / nombre / null=illimité)
  unit_price_xof NUMERIC(10,2),                           -- prix à l'unité (à la carte) ; NULL = non vendu seul
  category       TEXT,                                    -- 'chart','data','alerts','portfolio','ui'
  is_active      BOOLEAN NOT NULL DEFAULT true,
  display_order  INT NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 13bis.2 Panier de features par user (source = achat à l'unité, package, ou octroi admin)
CREATE TABLE IF NOT EXISTS user_features (
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  feature_key  TEXT NOT NULL REFERENCES features(key),
  value        JSONB NOT NULL DEFAULT 'true'::jsonb,     -- valeur accordée (true / nombre / null=illimité)
  source       TEXT NOT NULL DEFAULT 'addon' CHECK (source IN ('addon','package','grant')),
  source_ref   TEXT,                                      -- plan_code du package, id paiement, etc.
  granted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at   TIMESTAMPTZ,                               -- NULL = permanent
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, feature_key, source)
);
CREATE INDEX IF NOT EXISTS idx_user_features_user ON user_features(user_id);

CREATE TRIGGER trg_features_updated_at
  BEFORE UPDATE ON features
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_user_features_updated_at
  BEFORE UPDATE ON user_features
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 13bis.3 Seed catalogue : clés existantes (free_default = valeur du plan Free) + nouvelles features premium
INSERT INTO features (key, label, kind, free_default, category, display_order) VALUES
  ('history_years_max',          'Profondeur historique (années)', 'limit',   '3'::jsonb,    'data',      10),
  ('max_indicators_on_chart',    'Indicateurs simultanés',         'limit',   '2'::jsonb,    'chart',     20),
  ('multi_layout',               'Multi-graphes (layouts)',        'boolean', 'false'::jsonb,'chart',     30),
  ('realtime_candle',            'Bougie du jour temps réel',      'boolean', 'false'::jsonb,'chart',     40),
  ('ui_customization',           'Personnalisation UI',            'boolean', 'false'::jsonb,'ui',        50),
  ('max_watchlists',             'Listes de suivi',                'limit',   '2'::jsonb,    'data',      60),
  ('max_screener_saves',         'Screeners sauvegardés',          'limit',   '2'::jsonb,    'data',      70),
  ('max_virtual_portfolios',     'Portefeuilles virtuels',         'limit',   '1'::jsonb,    'portfolio', 80),
  ('max_real_portfolios',        'Portefeuilles réels',            'limit',   '0'::jsonb,    'portfolio', 90),
  ('max_alerts_email_active',    'Alertes email actives',          'limit',   '5'::jsonb,    'alerts',    100),
  ('max_alerts_whatsapp_active', 'Alertes WhatsApp actives',       'limit',   '3'::jsonb,    'alerts',    110)
ON CONFLICT (key) DO NOTHING;

-- 13bis.4 Résolution : carte d'entitlements effective d'un user.
-- = pour chaque feature active : la valeur accordée (non expirée, la plus récente) sinon free_default.
CREATE OR REPLACE FUNCTION get_user_entitlements(p_user UUID)
RETURNS JSONB
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(jsonb_object_agg(f.key, COALESCE(eff.value, f.free_default)), '{}'::jsonb)
  FROM features f
  LEFT JOIN LATERAL (
    SELECT uf.value
    FROM user_features uf
    WHERE uf.user_id = p_user
      AND uf.feature_key = f.key
      AND (uf.expires_at IS NULL OR uf.expires_at > now())
    ORDER BY uf.granted_at DESC
    LIMIT 1
  ) eff ON true
  WHERE f.is_active;
$$;

-- RLS : lecture publique du catalogue ; user lit/n'écrit que ses propres features (écriture = service role)
ALTER TABLE features ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_features ENABLE ROW LEVEL SECURITY;
CREATE POLICY read_all_features ON features FOR SELECT USING (true);
CREATE POLICY own_read_user_features ON user_features FOR SELECT USING (auth.uid() = user_id);

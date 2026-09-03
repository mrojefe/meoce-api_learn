-- ============================================================
-- AFRIVIEW V2 — Schéma PostgreSQL complet
-- Généré le : 2026-05-17
-- Zones : 1, 2, 3, 4 (partielle), 5, 6, 7, 8, 9, 10, 11, 12, 13 + audit_logs transversale
-- Tables : 53 (55 total quand Zone 4 finie — financial_metrics + financial_reports manquent)
-- Décisions : D1–D125
-- ============================================================
-- Ordre d'exécution respecte les dépendances FK (bas → haut)
-- ============================================================


-- ============================================================
-- EXTENSIONS POSTGRESQL
-- ============================================================
-- Activer AVANT toute création de table (sinon migration plante).
-- Sur Supabase, activables aussi via Dashboard > Database > Extensions.

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS vector;    -- pgvector pour boc_embeddings (D90)


-- ============================================================
-- UTILITAIRES
-- ============================================================

-- Trigger updated_at réutilisable (D34)
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Audit log table — transversale (D111). Tracée par process_audit_log() pour
-- toutes les tables business nécessitant un trail complet.
CREATE TABLE audit_logs (
  id          BIGSERIAL    PRIMARY KEY,
  table_name  TEXT         NOT NULL,
  record_id   TEXT         NOT NULL,
  action      TEXT         NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  old_data    JSONB,
  new_data    JSONB,
  changed_by  UUID,                                              -- D114 : sans FK pour indépendance
  changed_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_table_record ON audit_logs(table_name, record_id);
CREATE INDEX idx_audit_logs_changed_at   ON audit_logs(changed_at DESC);
CREATE INDEX idx_audit_logs_changed_by   ON audit_logs(changed_by) WHERE changed_by IS NOT NULL;

-- Trigger Audit générique (D112) — référence audit_logs créée juste au-dessus
CREATE OR REPLACE FUNCTION process_audit_log()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'UPDATE') THEN
    INSERT INTO audit_logs (table_name, record_id, action, old_data, new_data)
    VALUES (TG_TABLE_NAME, OLD.id::text, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;
  ELSIF (TG_OP = 'DELETE') THEN
    INSERT INTO audit_logs (table_name, record_id, action, old_data)
    VALUES (TG_TABLE_NAME, OLD.id::text, 'DELETE', to_jsonb(OLD));
    RETURN OLD;
  ELSIF (TG_OP = 'INSERT') THEN
    INSERT INTO audit_logs (table_name, record_id, action, new_data)
    VALUES (TG_TABLE_NAME, NEW.id::text, 'INSERT', to_jsonb(NEW));
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- ZONE 1 — RÉFÉRENTIEL MARCHÉ (7 tables)
-- D16–D26
-- ============================================================
-- ... (rest of the file until Zone 2)

CREATE TABLE currencies (
  code               CHAR(3)      PRIMARY KEY,
  name               TEXT         NOT NULL,
  symbol             TEXT,
  decimals           INT          NOT NULL DEFAULT 2,
  usd_exchange_rate  NUMERIC,
  last_updated       TIMESTAMPTZ  DEFAULT now()
);

INSERT INTO currencies (code, name, symbol, decimals, usd_exchange_rate) VALUES
  ('XOF', 'Franc CFA BCEAO', 'CFA', 0, 620.00),
  ('USD', 'US Dollar',       '$',   2,   1.00),
  ('EUR', 'Euro',            '€',   2,   0.92),
  ('NGN', 'Naira',           '₦',   2, 1500.00),
  ('MAD', 'Dirham marocain', 'DH',  2,  10.00),
  ('ZAR', 'Rand',            'R',   2,  18.50);

CREATE TABLE currency_rate_presets (
  code             TEXT       PRIMARY KEY,
  rate_multiplier  NUMERIC,
  display_order    INT        NOT NULL DEFAULT 0
);

INSERT INTO currency_rate_presets (code, rate_multiplier, display_order) VALUES
  ('conservative', 0.97, 1),
  ('moderate',     1.00, 2),
  ('aggressive',   1.03, 3),
  ('custom',       NULL, 4);

CREATE TABLE countries (
  code                  CHAR(2)   PRIMARY KEY,
  name                  TEXT      NOT NULL,
  region                TEXT,
  primary_currency_code CHAR(3)   REFERENCES currencies(code)
);

CREATE INDEX idx_countries_primary_currency ON countries(primary_currency_code);

INSERT INTO countries (code, name, region, primary_currency_code) VALUES
  ('CI', 'Côte d''Ivoire',  'West Africa',     'XOF'),
  ('SN', 'Sénégal',         'West Africa',     'XOF'),
  ('BF', 'Burkina Faso',    'West Africa',     'XOF'),
  ('ML', 'Mali',            'West Africa',     'XOF'),
  ('NG', 'Nigéria',         'West Africa',     'NGN'),
  ('MA', 'Maroc',           'North Africa',    'MAD'),
  ('ZA', 'Afrique du Sud',  'Southern Africa', 'ZAR');

CREATE TABLE sectors (
  id           SERIAL    PRIMARY KEY,
  name         TEXT      NOT NULL UNIQUE,
  code         TEXT      UNIQUE,
  description  TEXT
);

INSERT INTO sectors (name, code) VALUES
  ('finance',          'FIN'),
  ('industrie',        'IND'),
  ('agriculture',      'AGR'),
  ('distribution',     'DIS'),
  ('services_publics', 'SPU'),
  ('transport',        'TRA'),
  ('autres',           'OTH');

CREATE TABLE subsectors (
  id         SERIAL    PRIMARY KEY,
  sector_id  INT       NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
  name       TEXT      NOT NULL,
  code       TEXT,
  description TEXT,
  UNIQUE (sector_id, name)
);

CREATE INDEX idx_subsectors_sector ON subsectors(sector_id);

INSERT INTO subsectors (sector_id, name) VALUES
  ((SELECT id FROM sectors WHERE code='FIN'), 'banque_commerciale'),
  ((SELECT id FROM sectors WHERE code='FIN'), 'assurance_vie'),
  ((SELECT id FROM sectors WHERE code='FIN'), 'assurance_dommages'),
  ((SELECT id FROM sectors WHERE code='IND'), 'cimenterie'),
  ((SELECT id FROM sectors WHERE code='IND'), 'brasserie');

CREATE TABLE exchanges (
  id            SERIAL     PRIMARY KEY,
  code          TEXT       UNIQUE NOT NULL,
  name          TEXT       NOT NULL,
  country_code  CHAR(2)    REFERENCES countries(code),
  currency_code CHAR(3)    REFERENCES currencies(code),
  timezone      TEXT       NOT NULL,
  open_time     TIME,
  close_time    TIME,
  trading_days  INT[]      NOT NULL DEFAULT ARRAY[1,2,3,4,5],
  status        TEXT       NOT NULL DEFAULT 'active'
                           CHECK (status IN ('active','inactive')),
  CHECK (open_time < close_time)
);

CREATE INDEX idx_exchanges_country  ON exchanges(country_code);
CREATE INDEX idx_exchanges_currency ON exchanges(currency_code);

INSERT INTO exchanges (code, name, country_code, currency_code, timezone, open_time, close_time, trading_days) VALUES
  ('BRVM', 'Bourse Régionale des Valeurs Mobilières', 'CI', 'XOF',
   'Africa/Abidjan',    '09:00', '15:30', ARRAY[1,2,3,4,5]),
  ('NGX',  'Nigerian Exchange Group',                 'NG', 'NGN',
   'Africa/Lagos',      '10:00', '14:30', ARRAY[1,2,3,4,5]),
  ('CSE',  'Casablanca Stock Exchange',               'MA', 'MAD',
   'Africa/Casablanca', '09:30', '15:30', ARRAY[1,2,3,4,5]);

-- user_exchange_rates dépend de users (Zone 5) — défini après


-- ============================================================
-- ZONE 2 — INSTRUMENT HUB (2 tables)
-- D27–D34
-- ============================================================

CREATE TABLE instrument_types (
  code          TEXT     PRIMARY KEY,
  display_order INT      NOT NULL DEFAULT 0,
  is_tradable   BOOLEAN  NOT NULL DEFAULT true
);

INSERT INTO instrument_types (code, display_order, is_tradable) VALUES
  ('stock',   1, true),
  ('bond',    2, true),
  ('etf',     3, true),
  ('sukuk',   4, true),
  ('right',   5, true),
  ('warrant', 6, true),
  ('index',   7, false);

CREATE TABLE instruments (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  exchange_id   INT          NOT NULL REFERENCES exchanges(id),
  symbol        TEXT         NOT NULL,
  name          TEXT         NOT NULL,
  isin          CHAR(12),
  type          TEXT         NOT NULL REFERENCES instrument_types(code),
  currency_code CHAR(3)      NOT NULL REFERENCES currencies(code),
  sector_id     INT          NOT NULL REFERENCES sectors(id),
  subsector_id  INT          REFERENCES subsectors(id),
  country_code  CHAR(2)      REFERENCES countries(code),
  status        TEXT         NOT NULL DEFAULT 'active'
                             CHECK (status IN ('active','delisted','suspended','pending_listing')),
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (exchange_id, symbol)
);

CREATE INDEX idx_instruments_symbol        ON instruments(symbol);
CREATE INDEX idx_instruments_exchange      ON instruments(exchange_id);
CREATE INDEX idx_instruments_sector        ON instruments(sector_id);
CREATE INDEX idx_instruments_subsector     ON instruments(subsector_id);
CREATE INDEX idx_instruments_country       ON instruments(country_code);
CREATE INDEX idx_instruments_currency      ON instruments(currency_code);
CREATE INDEX idx_instruments_type          ON instruments(type);
CREATE INDEX idx_instruments_status_active ON instruments(status) WHERE status = 'active';
CREATE INDEX idx_instruments_isin          ON instruments(isin) WHERE isin IS NOT NULL;

CREATE TRIGGER trg_instruments_updated_at
  BEFORE UPDATE ON instruments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_audit_instruments
  AFTER INSERT OR UPDATE OR DELETE ON instruments
  FOR EACH ROW EXECUTE FUNCTION process_audit_log();


-- ============================================================
-- ZONE 3 — MARCHÉ (6 tables)
-- D35–D46
-- ============================================================

CREATE TABLE intraday_meta_data (
  instrument_id    UUID         NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  market_date      DATE         NOT NULL,
  open_price       NUMERIC,
  previous_close   NUMERIC,
  preopen_price    NUMERIC,
  preopen_quantity BIGINT,
  static_limit_up  NUMERIC,
  static_limit_down NUMERIC,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (instrument_id, market_date)
);

CREATE TABLE intraday_snapshots (
  id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  instrument_id        UUID         NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  market_date          DATE         NOT NULL,
  scraped_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
  last_trade_price     NUMERIC      CHECK (last_trade_price IS NULL OR last_trade_price > 0),
  last_trade_variation NUMERIC,
  high_price           NUMERIC,
  low_price            NUMERIC,
  weighted_avg_price   NUMERIC,
  quantity_cumul       BIGINT       DEFAULT 0 CHECK (quantity_cumul >= 0),
  value_cumul          NUMERIC      DEFAULT 0 CHECK (value_cumul >= 0),
  trade_state          TEXT,
  carnet_hash          TEXT,
  created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (instrument_id, scraped_at)
);

CREATE INDEX idx_intraday_snap_instr_date_scraped
  ON intraday_snapshots(instrument_id, market_date, scraped_at DESC);
CREATE INDEX idx_intraday_snap_carnet_hash
  ON intraday_snapshots(carnet_hash) WHERE carnet_hash IS NOT NULL;

CREATE TABLE intraday_chart_points (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  instrument_id UUID         NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  market_date   DATE         NOT NULL,
  timestamp_ms  BIGINT       NOT NULL,
  price         NUMERIC      NOT NULL CHECK (price > 0),
  UNIQUE (instrument_id, timestamp_ms)
);

CREATE INDEX idx_chart_points_instr_date
  ON intraday_chart_points(instrument_id, market_date);

CREATE TABLE intraday_transactions (
  id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  instrument_id      UUID         NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  market_date        DATE         NOT NULL,
  trade_timestamp    TIMESTAMPTZ  NOT NULL,
  price              NUMERIC      NOT NULL CHECK (price > 0),
  quantity           INT          NOT NULL CHECK (quantity > 0),
  value              NUMERIC      NOT NULL CHECK (value > 0),
  variation_at_trade NUMERIC,
  value_cumul_after  NUMERIC,
  UNIQUE (instrument_id, trade_timestamp)
);

CREATE INDEX idx_tx_instr_date
  ON intraday_transactions(instrument_id, market_date DESC, trade_timestamp DESC);

CREATE TABLE order_book_levels (
  instrument_id        UUID         NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  market_date          DATE         NOT NULL,
  carnet_hash          TEXT         NOT NULL,
  rank                 INT          NOT NULL CHECK (rank >= 1),
  position             INT          CHECK (position >= 1),
  buy_price            NUMERIC,
  buy_quantity         NUMERIC,
  buy_number_of_orders INT,
  sell_price           NUMERIC,
  sell_quantity        NUMERIC,
  sell_number_of_orders INT,
  first_seen_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  last_seen_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (instrument_id, market_date, carnet_hash, rank)
);

CREATE INDEX idx_orderbook_instr_date ON order_book_levels(instrument_id, market_date);

CREATE TABLE daily_candles (
  instrument_id  UUID         NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  date           DATE         NOT NULL,
  open_price     NUMERIC      NOT NULL CHECK (open_price > 0),
  high_price     NUMERIC      NOT NULL CHECK (high_price > 0),
  low_price      NUMERIC      NOT NULL CHECK (low_price > 0),
  close_price    NUMERIC      NOT NULL CHECK (close_price > 0),
  previous_close NUMERIC,
  quantity       BIGINT       NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  value          NUMERIC      NOT NULL DEFAULT 0 CHECK (value >= 0),
  change_percent NUMERIC,
  trade_count    INT          CHECK (trade_count IS NULL OR trade_count >= 0),
  source         TEXT         NOT NULL DEFAULT 'sikafinance'
                              CHECK (source IN ('sikafinance','sgi_eod','boc_pdf','manual','other')),
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (instrument_id, date),
  CHECK (high_price >= low_price),
  CHECK (high_price >= open_price AND high_price >= close_price),
  CHECK (low_price  <= open_price AND low_price  <= close_price)
);

CREATE INDEX idx_daily_candles_date ON daily_candles(date);

CREATE TRIGGER trg_daily_candles_updated_at
  BEFORE UPDATE ON daily_candles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();


-- ============================================================
-- ZONE 5 — AUTH & UTILISATEURS (1 table)
-- D47–D50
-- Supabase Auth gère auth.users — on étend avec un profil public
-- ============================================================

CREATE TABLE users (
  id           UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username     TEXT        UNIQUE,
  email        TEXT        UNIQUE,                      -- D48 : nullable (signup WhatsApp possible)
  phone        TEXT        UNIQUE,
  first_name   TEXT,
  last_name    TEXT,
  display_name TEXT,                                    -- D50
  bio          TEXT,                                    -- D50
  avatar_url   TEXT,                                    -- D50
  status       TEXT        NOT NULL DEFAULT 'active'
                           CHECK (status IN ('active','suspended','banned')),
  role         TEXT        NOT NULL DEFAULT 'user'
                           CHECK (role IN ('user','admin','api_client')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login   TIMESTAMPTZ
);

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- user_exchange_rates (Zone 1 — dépend de users)
CREATE TABLE user_exchange_rates (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  from_currency CHAR(3)      NOT NULL REFERENCES currencies(code),
  to_currency   CHAR(3)      NOT NULL REFERENCES currencies(code),
  rate          NUMERIC      NOT NULL CHECK (rate > 0),
  preset_code   TEXT         NOT NULL REFERENCES currency_rate_presets(code),
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (user_id, from_currency, to_currency),
  CHECK (from_currency <> to_currency)
);

CREATE INDEX idx_user_rates_user ON user_exchange_rates(user_id);

CREATE TRIGGER trg_user_exchange_rates_updated_at
  BEFORE UPDATE ON user_exchange_rates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();


-- ============================================================
-- ZONE 6 — PERSONNALISATION (7 tables)
-- D51–D63
-- ============================================================

CREATE TABLE watchlists (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT        NOT NULL,
  description TEXT,
  is_public   BOOLEAN     NOT NULL DEFAULT false,       -- D58
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_watchlists_user ON watchlists(user_id);

CREATE TRIGGER trg_watchlists_updated_at
  BEFORE UPDATE ON watchlists
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE watchlist_items (
  watchlist_id  UUID          NOT NULL REFERENCES watchlists(id) ON DELETE CASCADE,
  instrument_id UUID          NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  added_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
  sort_order    INT,
  alert_enabled BOOLEAN       NOT NULL DEFAULT false,
  target_price  NUMERIC(18,4),
  notes         TEXT,
  PRIMARY KEY (watchlist_id, instrument_id)
);

CREATE TABLE user_instrument_flags (
  user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  instrument_id UUID        NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  flag_color    TEXT        NOT NULL
                            CHECK (flag_color IN ('red','orange','yellow','green','blue')),  -- D53
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, instrument_id)
);

CREATE TRIGGER trg_user_instrument_flags_updated_at
  BEFORE UPDATE ON user_instrument_flags
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE user_preferences (
  user_id              UUID    PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  default_currency     CHAR(3) REFERENCES currencies(code),       -- D49 : pas de FK directe sur users
  default_language     TEXT,                                      -- code ex: 'fr','en' (D25)
  default_timeframe    TEXT,                                      -- D51 : TEXT libre, validation API
  default_chart_type   TEXT
                       CHECK (default_chart_type IS NULL OR default_chart_type IN (
                         'candlestick','bar','line','area','heikin_ashi','renko'  -- D52
                       )),
  default_watchlist_id UUID    REFERENCES watchlists(id) ON DELETE SET NULL,
  default_template_id  UUID,  -- FK ajoutée plus bas (chart_templates créé après)
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_user_preferences_updated_at
  BEFORE UPDATE ON user_preferences
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE chart_templates (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name             TEXT        NOT NULL,
  chart_type       TEXT        NOT NULL                        -- D52 : liste finie stable
                               CHECK (chart_type IN ('candlestick','bar','line','area','heikin_ashi','renko')),
  indicators       JSONB       NOT NULL DEFAULT '[]',          -- D56 : combo réutilisable
  visual_settings  JSONB       NOT NULL DEFAULT '{}',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_chart_templates_user ON chart_templates(user_id);

CREATE TRIGGER trg_chart_templates_updated_at
  BEFORE UPDATE ON chart_templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- FK différée : user_preferences créé avant chart_templates (FK croisée)
ALTER TABLE user_preferences
  ADD CONSTRAINT user_preferences_default_template_fk
  FOREIGN KEY (default_template_id) REFERENCES chart_templates(id) ON DELETE SET NULL;

CREATE INDEX idx_user_preferences_default_template
  ON user_preferences(default_template_id)
  WHERE default_template_id IS NOT NULL;

CREATE TABLE chart_drawings (
  user_id       UUID  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  instrument_id UUID  NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  timeframe     TEXT  NOT NULL,
  drawings      JSONB NOT NULL DEFAULT '[]',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, instrument_id, timeframe)
);

CREATE TRIGGER trg_chart_drawings_updated_at
  BEFORE UPDATE ON chart_drawings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE indicator_preferences (
  user_id    UUID  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  timeframe  TEXT  NOT NULL,
  indicators JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, timeframe)
);

CREATE TRIGGER trg_indicator_preferences_updated_at
  BEFORE UPDATE ON indicator_preferences
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();


-- ============================================================
-- ZONE 7 — PORTFOLIO (4 tables)
-- D64–D75, D83
-- ============================================================

CREATE TABLE portfolios (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name             TEXT        NOT NULL,
  description      TEXT,
  type             TEXT        NOT NULL DEFAULT 'virtual'
                               CHECK (type IN ('real','virtual','demo')),
  status           TEXT        NOT NULL DEFAULT 'active'
                               CHECK (status IN ('active','archived','deleted')),
  base_currency    CHAR(3)     NOT NULL REFERENCES currencies(code),
  default_fee_rate NUMERIC(6,4),
  source           TEXT        NOT NULL DEFAULT 'manual'
                               CHECK (source IN ('manual','pdf_import')),
  is_public        BOOLEAN     NOT NULL DEFAULT false,
  deleted_at       TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_portfolios_user ON portfolios(user_id);

CREATE TRIGGER trg_portfolios_updated_at
  BEFORE UPDATE ON portfolios
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE positions (
  portfolio_id  UUID          NOT NULL REFERENCES portfolios(id) ON DELETE CASCADE,
  instrument_id UUID          NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  direction     TEXT          NOT NULL DEFAULT 'long'
                              CHECK (direction IN ('long','short')),
  quantity      NUMERIC(18,6) NOT NULL DEFAULT 0,
  avg_cost      NUMERIC(18,4) NOT NULL DEFAULT 0,
  realized_pnl  NUMERIC(18,4) NOT NULL DEFAULT 0,
  status        TEXT          NOT NULL DEFAULT 'open'
                              CHECK (status IN ('open','closed')),
  notes         TEXT,
  opened_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
  PRIMARY KEY (portfolio_id, instrument_id)
);

CREATE TRIGGER trg_positions_updated_at
  BEFORE UPDATE ON positions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE portfolio_transactions (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  portfolio_id  UUID          NOT NULL REFERENCES portfolios(id) ON DELETE CASCADE,
  instrument_id UUID          REFERENCES instruments(id),
  type          TEXT          NOT NULL
                              CHECK (type IN ('buy','sell','dividend','deposit','withdrawal')),
  quantity      NUMERIC(18,6),
  price         NUMERIC(18,4),
  fees          NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_amount  NUMERIC(18,4) NOT NULL,
  executed_at   TIMESTAMPTZ   NOT NULL,
  notes         TEXT
);

CREATE INDEX idx_portfolio_tx_portfolio  ON portfolio_transactions(portfolio_id);
CREATE INDEX idx_portfolio_tx_instrument ON portfolio_transactions(instrument_id)
  WHERE instrument_id IS NOT NULL;

CREATE TABLE portfolio_snapshots (
  portfolio_id       UUID    NOT NULL REFERENCES portfolios(id) ON DELETE CASCADE,
  snapshot_date      DATE    NOT NULL,
  total_value        NUMERIC(18,4) NOT NULL,
  cash_balance       NUMERIC(18,4) NOT NULL DEFAULT 0,
  invested_amount    NUMERIC(18,4) NOT NULL,
  total_pnl          NUMERIC(18,4) NOT NULL,
  daily_return       NUMERIC(10,6),
  cumulative_return  NUMERIC(10,6),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (portfolio_id, snapshot_date)
);


-- ============================================================
-- ZONE 8 — ALERTES (3 tables)
-- D76–D80
-- ============================================================

CREATE TABLE alert_rules (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  instrument_id UUID        NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  rule_type     TEXT        NOT NULL
                            CHECK (rule_type IN ('price_above','price_below','percent_change','volume_above')),
  threshold     NUMERIC     NOT NULL,
  channels      TEXT[]      NOT NULL DEFAULT ARRAY['in_app']      -- D122 : canaux par alerte
                            CHECK (channels <@ ARRAY['email','whatsapp','push','in_app']
                                   AND array_length(channels, 1) >= 1),
  is_active     BOOLEAN     NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_alert_rules_user         ON alert_rules(user_id);
CREATE INDEX idx_alert_rules_instrument   ON alert_rules(instrument_id);
CREATE INDEX idx_alert_rules_channels_gin ON alert_rules USING gin(channels);     -- D122 fix Opus
CREATE INDEX idx_alert_rules_active       ON alert_rules(user_id, is_active)
  WHERE is_active = true;                                                          -- D125 : query quota actif

CREATE TRIGGER trg_alert_rules_updated_at
  BEFORE UPDATE ON alert_rules
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE alert_notifications (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id       UUID        NOT NULL REFERENCES alert_rules(id) ON DELETE CASCADE,
  triggered_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  trigger_value NUMERIC     NOT NULL,
  channel       TEXT        NOT NULL CHECK (channel IN ('email','whatsapp','push','in_app')),
  status        TEXT        NOT NULL CHECK (status IN ('sent','failed'))
);

CREATE INDEX idx_alert_notif_rule ON alert_notifications(rule_id);

CREATE TABLE user_notification_settings (
  user_id           UUID    PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  email_enabled     BOOLEAN NOT NULL DEFAULT true,
  whatsapp_enabled  BOOLEAN NOT NULL DEFAULT false,
  push_enabled      BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_user_notif_settings_updated_at
  BEFORE UPDATE ON user_notification_settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();


-- ============================================================
-- ZONE 9 — IVI (8 tables)
-- D81–D87, D92–D96
-- ============================================================

CREATE TABLE ivi_variants (
  code          TEXT    PRIMARY KEY,
  name          TEXT    NOT NULL,
  system_prompt TEXT    NOT NULL,
  config        JSONB   NOT NULL DEFAULT '{}',
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_ivi_variants_updated_at
  BEFORE UPDATE ON ivi_variants
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

INSERT INTO ivi_variants (code, name, system_prompt, config) VALUES
  ('base',   'Ivi',        'Tu es Ivi, assistante Afriview spécialisée dans les marchés financiers africains.', '{}'),
  ('mentor', 'Ivi Mentor', 'Tu es Ivi Mentor, tu expliques les concepts financiers de façon pédagogique.', '{}'),
  ('dev',    'Ivi Dev',    'Tu es Ivi Dev, tu aides avec les intégrations techniques et l''API Afriview.', '{}');

CREATE TABLE ivi_conversations (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  variant_code TEXT        NOT NULL REFERENCES ivi_variants(code) DEFAULT 'base',
  title        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ivi_conversations_user    ON ivi_conversations(user_id);
CREATE INDEX idx_ivi_conversations_variant ON ivi_conversations(variant_code);

CREATE TRIGGER trg_ivi_conversations_updated_at
  BEFORE UPDATE ON ivi_conversations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE ivi_messages (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID        NOT NULL REFERENCES ivi_conversations(id) ON DELETE CASCADE,
  role            TEXT        NOT NULL CHECK (role IN ('user','assistant')),
  content         TEXT        NOT NULL,
  is_edited       BOOLEAN     NOT NULL DEFAULT false,
  has_attachments BOOLEAN     NOT NULL DEFAULT false,
  is_superseded   BOOLEAN     NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  -- Pas de updated_at : append-only sauf exception dernier message user (D85)
);

CREATE INDEX idx_ivi_messages_conversation ON ivi_messages(conversation_id);

CREATE TABLE ivi_message_edits (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id       UUID        NOT NULL REFERENCES ivi_messages(id) ON DELETE CASCADE,
  original_content TEXT        NOT NULL,
  edited_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ivi_message_edits_message ON ivi_message_edits(message_id);

CREATE TABLE ivi_message_attachments (
  id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id      UUID    NOT NULL REFERENCES ivi_messages(id) ON DELETE CASCADE,
  attachment_type TEXT    NOT NULL DEFAULT 'file'
                          CHECK (attachment_type IN ('file','portfolio_import')),
  r2_key          TEXT    NOT NULL,
  filename        TEXT    NOT NULL,
  mime_type       TEXT    NOT NULL,
  size_bytes      INT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ivi_message_attachments_message ON ivi_message_attachments(message_id);

CREATE TABLE ivi_actions (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id    UUID        NOT NULL REFERENCES ivi_messages(id) ON DELETE CASCADE,
  action_type   TEXT        NOT NULL,
  payload       JSONB       NOT NULL DEFAULT '{}',
  status        TEXT        NOT NULL DEFAULT 'pending_validation'
                            CHECK (status IN ('pending_validation','validated','rejected','executed','failed')),
  error_message TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ivi_actions_message ON ivi_actions(message_id);

CREATE TRIGGER trg_ivi_actions_updated_at
  BEFORE UPDATE ON ivi_actions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE screener_templates (
  id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name      TEXT        NOT NULL,
  criteria  JSONB       NOT NULL DEFAULT '[]',
  action_id UUID        REFERENCES ivi_actions(id) ON DELETE SET NULL,
  is_public BOOLEAN     NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_screener_templates_user   ON screener_templates(user_id);
CREATE INDEX idx_screener_templates_action ON screener_templates(action_id)
  WHERE action_id IS NOT NULL;

CREATE TRIGGER trg_screener_templates_updated_at
  BEFORE UPDATE ON screener_templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE custom_metrics (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       TEXT        NOT NULL,
  formula    TEXT        NOT NULL,
  action_id  UUID        REFERENCES ivi_actions(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_custom_metrics_user   ON custom_metrics(user_id);
CREATE INDEX idx_custom_metrics_action ON custom_metrics(action_id)
  WHERE action_id IS NOT NULL;

CREATE TRIGGER trg_custom_metrics_updated_at
  BEFORE UPDATE ON custom_metrics
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();


-- ============================================================
-- ZONE 10 — BOC (3 tables)
-- D88–D91
-- ============================================================

CREATE TABLE boc_documents (
  id           UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  boc_date     DATE    NOT NULL UNIQUE,
  source_url   TEXT    NOT NULL,
  r2_key       TEXT    NOT NULL,
  file_hash    TEXT    NOT NULL UNIQUE,
  content_hash TEXT    UNIQUE,
  status       TEXT    NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','processed','failed')),
  page_count   INT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_boc_documents_updated_at
  BEFORE UPDATE ON boc_documents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Extension vector déclarée en tête de fichier

CREATE TABLE boc_embeddings (
  id           UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id  UUID    NOT NULL REFERENCES boc_documents(id) ON DELETE CASCADE,
  tier         TEXT    NOT NULL CHECK (tier IN ('tier1','tier2')),
  chunk_index  INT     NOT NULL,
  chunk_text   TEXT    NOT NULL,
  embedding    vector(1536) NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_boc_embeddings_document ON boc_embeddings(document_id);
-- Index kNN à créer après chargement des données :
-- CREATE INDEX idx_boc_embeddings_ivfflat ON boc_embeddings
--   USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

CREATE TABLE boc_instrument_mentions (
  id            UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id   UUID    NOT NULL REFERENCES boc_documents(id) ON DELETE CASCADE,
  instrument_id UUID    NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  mention_type  TEXT    NOT NULL
                        CHECK (mention_type IN ('cours','dividende','annonce','resultat')),
  context       TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (document_id, instrument_id, mention_type)
);

CREATE INDEX idx_boc_mentions_document   ON boc_instrument_mentions(document_id);
CREATE INDEX idx_boc_mentions_instrument ON boc_instrument_mentions(instrument_id);


-- ============================================================
-- ZONE 11 — PLATEFORME (3 tables)
-- D97–D99
-- ============================================================

CREATE TABLE feature_proposals (
  id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       TEXT    NOT NULL,
  description TEXT    NOT NULL,
  category    TEXT    NOT NULL CHECK (category IN ('feature','bug','improvement')),
  status      TEXT    NOT NULL DEFAULT 'open'
                      CHECK (status IN ('open','planned','in_progress','done','rejected')),
  vote_count  INT     NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_feature_proposals_updated_at
  BEFORE UPDATE ON feature_proposals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE proposal_attachments (
  id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  proposal_id UUID    NOT NULL REFERENCES feature_proposals(id) ON DELETE CASCADE,
  r2_key      TEXT    NOT NULL,
  filename    TEXT    NOT NULL,
  mime_type   TEXT    NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_proposal_attachments_proposal ON proposal_attachments(proposal_id);

CREATE TABLE proposal_votes (
  proposal_id UUID    NOT NULL REFERENCES feature_proposals(id) ON DELETE CASCADE,
  user_id     UUID    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (proposal_id, user_id)
);

-- PK composite couvre proposal_id (1ère colonne) — index supplémentaire sur user_id
CREATE INDEX idx_proposal_votes_user ON proposal_votes(user_id);

-- Trigger synchronisation vote_count (D97) — denormalisation maintenue par la DB
CREATE OR REPLACE FUNCTION update_proposal_vote_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE feature_proposals SET vote_count = vote_count + 1
      WHERE id = NEW.proposal_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE feature_proposals SET vote_count = vote_count - 1
      WHERE id = OLD.proposal_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_proposal_votes_count
  AFTER INSERT OR DELETE ON proposal_votes
  FOR EACH ROW EXECUTE FUNCTION update_proposal_vote_count();

-- audit_logs : déplacée en tête de fichier (D111) — transversale, pas Zone 11


-- ============================================================
-- ZONE 4 — FONDAMENTAUX (en cours 2026-05-15)
-- D109–D112 — design itératif
-- Tables : dividends ✅, corporate_actions ✅, financial_metrics ⏳, financial_reports ⏳
-- ============================================================

-- 4.1 dividends : événements de versement par instrument (approche C)
-- D110 : cancel pattern pour annulations légales (append-only)
-- + updated_at pour corrections normales (typos, dates affinées)
-- + audit_logs (D111) pour traçabilité complète
CREATE TABLE dividends (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  instrument_id       UUID          NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  declaration_date    DATE          NOT NULL,
  ex_date             DATE,
  record_date         DATE,
  payment_date        DATE,
  amount              NUMERIC(18,6) NOT NULL,
  currency_code       CHAR(3)       NOT NULL REFERENCES currencies(code),
  type                TEXT          NOT NULL
                                    CHECK (type IN ('cash','stock','special','scrip','cancel')),
  cancels_dividend_id UUID          REFERENCES dividends(id) ON DELETE SET NULL,  -- D110
  source              TEXT,                                                       -- pas de CHECK
  notes               TEXT,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  CHECK ((type = 'cancel'  AND amount < 0 AND cancels_dividend_id IS NOT NULL)
      OR (type <> 'cancel' AND amount > 0 AND cancels_dividend_id IS NULL)),
  CHECK (cancels_dividend_id IS NULL OR cancels_dividend_id <> id),  -- D119 : pas d'auto-référence
  UNIQUE (instrument_id, declaration_date, type)
);

CREATE INDEX idx_dividends_instrument ON dividends(instrument_id);
CREATE INDEX idx_dividends_ex_date    ON dividends(ex_date)  WHERE ex_date  IS NOT NULL;
CREATE INDEX idx_dividends_currency   ON dividends(currency_code);
CREATE INDEX idx_dividends_cancels    ON dividends(cancels_dividend_id) WHERE cancels_dividend_id IS NOT NULL;

CREATE TRIGGER trg_dividends_updated_at
  BEFORE UPDATE ON dividends FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_audit_dividends
  AFTER INSERT OR UPDATE OR DELETE ON dividends
  FOR EACH ROW EXECUTE FUNCTION process_audit_log();


-- 4.2 corporate_actions : événements structurants (splits, mergers, delistings)
-- D113 : type CHECK (12 valeurs), status CHECK (3 valeurs)
-- D116 : effective_date NULLABLE — annonce possible sans date effective connue
-- ratio + target_instrument_id : colonnes typées pour les cas fréquents (anti-JSONB-only)
CREATE TABLE corporate_actions (
  id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  instrument_id         UUID         NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  type                  TEXT         NOT NULL CHECK (type IN (
                                       'split','reverse_split',
                                       'merger','acquisition','spin_off',
                                       'rights_issue','buyback','tender_offer',
                                       'ipo','delisting','suspension','name_change'
                                     )),
  announcement_date     DATE         NOT NULL,
  effective_date        DATE,                                                -- D116 : nullable
  status                TEXT         NOT NULL DEFAULT 'announced'
                                     CHECK (status IN ('announced','effective','cancelled')),
  ratio                 NUMERIC,                                              -- splits : nouvelles / 1 ancienne
  target_instrument_id  UUID         REFERENCES instruments(id) ON DELETE SET NULL,  -- mergers/acquisitions/spin_off
  details               JSONB        NOT NULL DEFAULT '{}'::jsonb,           -- spécifique au type
  source                TEXT,
  notes                 TEXT,
  created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CHECK (ratio IS NULL OR type IN ('split','reverse_split')),
  CHECK (target_instrument_id IS NULL OR type IN ('merger','acquisition','spin_off'))
);

CREATE INDEX idx_corporate_actions_instrument ON corporate_actions(instrument_id);
CREATE INDEX idx_corporate_actions_target     ON corporate_actions(target_instrument_id)
  WHERE target_instrument_id IS NOT NULL;
CREATE INDEX idx_corporate_actions_effective  ON corporate_actions(effective_date)
  WHERE effective_date IS NOT NULL;
CREATE INDEX idx_corporate_actions_type       ON corporate_actions(type);

-- Trigger sync instruments.status — fix bug Opus :
-- Fire UNIQUEMENT si status='effective' ET effective_date passée
CREATE OR REPLACE FUNCTION update_instrument_status_on_ca()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.type = 'delisting'
     AND NEW.status = 'effective'
     AND NEW.effective_date IS NOT NULL
     AND NEW.effective_date <= CURRENT_DATE THEN
    UPDATE instruments SET status = 'delisted' WHERE id = NEW.instrument_id;
  ELSIF NEW.type = 'suspension'
        AND NEW.status = 'effective'
        AND NEW.effective_date IS NOT NULL
        AND NEW.effective_date <= CURRENT_DATE THEN
    UPDATE instruments SET status = 'suspended' WHERE id = NEW.instrument_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_instrument_status
  AFTER INSERT OR UPDATE ON corporate_actions
  FOR EACH ROW EXECUTE FUNCTION update_instrument_status_on_ca();

CREATE TRIGGER trg_corporate_actions_updated_at
  BEFORE UPDATE ON corporate_actions FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_audit_corporate_actions
  AFTER INSERT OR UPDATE OR DELETE ON corporate_actions
  FOR EACH ROW EXECUTE FUNCTION process_audit_log();

-- 4.3 financial_metrics : métriques calculées (P/E, Yield) ⏳
-- 4.4 financial_reports : rapports annuels/trimestriels ⏳


-- ============================================================
-- ZONE 12 — ACTUALITÉS & MACRO (V1 Priority)
-- D115–D117 — Contenu vivant pour le lancement
-- ============================================================

-- 12.1 news_sources : sources d'actualités (BRVM, Agence Ecofin, etc.)
CREATE TABLE news_sources (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT         NOT NULL UNIQUE,
  url         TEXT,
  type        TEXT         NOT NULL CHECK (type IN ('official','media','agency','blog','social')),
  rss_url     TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_news_sources_type ON news_sources(type);

CREATE TRIGGER trg_news_sources_updated_at
  BEFORE UPDATE ON news_sources FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 12.2 news_articles : articles agrégés/scrapés
-- D117 : url_hash (UNIQUE) au lieu de url UNIQUE — gère tracking params (?utm_source=...)
-- et ré-écritures de canonical URL côté source
CREATE TABLE news_articles (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id     UUID         NOT NULL REFERENCES news_sources(id) ON DELETE CASCADE,
  title         TEXT         NOT NULL,
  summary       TEXT,
  content       TEXT,
  url           TEXT,                                                      -- informatif (peut varier)
  url_hash      TEXT         NOT NULL UNIQUE,                              -- D117 : SHA-256 de URL normalisée
  published_at  TIMESTAMPTZ,
  sentiment     TEXT         CHECK (sentiment IS NULL OR sentiment IN ('positive','negative','neutral')),
  tags          TEXT[],                                                    -- recherche full-text rapide
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_news_articles_published_at ON news_articles(published_at DESC) WHERE published_at IS NOT NULL;
CREATE INDEX idx_news_articles_source       ON news_articles(source_id);
CREATE INDEX idx_news_articles_sentiment    ON news_articles(sentiment) WHERE sentiment IS NOT NULL;

CREATE TRIGGER trg_news_articles_updated_at
  BEFORE UPDATE ON news_articles FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_audit_news_articles
  AFTER INSERT OR UPDATE OR DELETE ON news_articles
  FOR EACH ROW EXECUTE FUNCTION process_audit_log();

-- 12.3 news_article_instruments : junction N-N (remplace UUID[] anti-pattern D117)
CREATE TABLE news_article_instruments (
  article_id     UUID  NOT NULL REFERENCES news_articles(id) ON DELETE CASCADE,
  instrument_id  UUID  NOT NULL REFERENCES instruments(id) ON DELETE CASCADE,
  relevance      NUMERIC(3,2) CHECK (relevance IS NULL OR (relevance >= 0 AND relevance <= 1)),
  PRIMARY KEY (article_id, instrument_id)
);

CREATE INDEX idx_news_art_instr_instrument ON news_article_instruments(instrument_id);

-- 12.4 economic_indicators : données macro-économiques (PIB, Inflation)
CREATE TABLE economic_indicators (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT         NOT NULL,
  value       NUMERIC      NOT NULL,
  unit        TEXT,                                                       -- '%','XOF','points'
  date        DATE         NOT NULL,
  source_id   UUID         REFERENCES news_sources(id) ON DELETE SET NULL,
  frequency   TEXT         CHECK (frequency IS NULL OR frequency IN ('daily','weekly','monthly','quarterly','yearly')),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (name, date)
);

CREATE INDEX idx_economic_indicators_name   ON economic_indicators(name);
CREATE INDEX idx_economic_indicators_date   ON economic_indicators(date DESC);
CREATE INDEX idx_economic_indicators_source ON economic_indicators(source_id) WHERE source_id IS NOT NULL;

CREATE TRIGGER trg_economic_indicators_updated_at
  BEFORE UPDATE ON economic_indicators FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_audit_economic_indicators
  AFTER INSERT OR UPDATE OR DELETE ON economic_indicators
  FOR EACH ROW EXECUTE FUNCTION process_audit_log();


-- ============================================================
-- ZONE 13 — SUBSCRIPTIONS & QUOTAS (D120-D125)
-- ============================================================
-- Système Freemium "features" — pricing tier free/premium V1.
-- Quotas = compteurs d'objets ACTIFS (D125 — style TradingView/Notion).
-- Enforcement = app-level (D123) pour erreurs métier propres.
-- Widgets B2B (api_keys) = système séparé V2.
-- Voir : document_bd/PRICING_TIERS_V1.md
-- ============================================================

-- 13.1 subscription_plans : catalogue des plans (admin via Supabase Studio)
CREATE TABLE subscription_plans (
  code              TEXT          PRIMARY KEY,            -- 'free','premium'
  name              TEXT          NOT NULL,
  monthly_price_xof NUMERIC(10,2),                        -- NULL pour free / prix à acter
  yearly_price_xof  NUMERIC(10,2),                        -- NULL pour free / prix à acter
  features          JSONB         NOT NULL DEFAULT '{}',  -- D124 : flexibilité limites
  is_active         BOOLEAN       NOT NULL DEFAULT true,
  display_order     INT           NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_subscription_plans_updated_at
  BEFORE UPDATE ON subscription_plans
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Seed initial : free + premium (limites détaillées dans PRICING_TIERS_V1.md)
INSERT INTO subscription_plans (code, name, monthly_price_xof, yearly_price_xof, features, display_order) VALUES
  ('free', 'Free', NULL, NULL, '{
    "max_watchlists": 2,
    "max_virtual_portfolios": 1,
    "max_real_portfolios": 0,
    "max_alerts_email_active": 5,
    "max_alerts_whatsapp_active": 3,
    "max_screener_saves": 2,
    "max_indicators_on_chart": 2,
    "history_years_default": 3,
    "history_years_max": 3,
    "ui_customization": false,
    "news_feed": true
  }'::jsonb, 0),
  ('premium', 'Premium', NULL, NULL, '{
    "max_watchlists": null,
    "max_virtual_portfolios": null,
    "max_real_portfolios": 3,
    "max_alerts_email_active": 50,
    "max_alerts_whatsapp_active": 20,
    "max_screener_saves": 10,
    "max_indicators_on_chart": null,
    "history_years_default": null,
    "history_years_max": null,
    "ui_customization": true,
    "news_feed": true
  }'::jsonb, 1);

-- 13.2 subscriptions : user → plan
CREATE TABLE subscriptions (
  id                       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_code                TEXT         NOT NULL REFERENCES subscription_plans(code),
  status                   TEXT         NOT NULL DEFAULT 'active'
                                        CHECK (status IN ('trial','active','past_due','cancelled','expired')),
  started_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
  current_period_start     TIMESTAMPTZ  NOT NULL DEFAULT now(),
  current_period_end       TIMESTAMPTZ,                        -- NULL pour free (pas d'expiration)
  cancelled_at             TIMESTAMPTZ,
  cancellation_reason      TEXT,
  payment_provider         TEXT,                                -- 'wave','orange_money','flutterwave'
  external_subscription_id TEXT,                                -- ID chez le provider
  created_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_subscriptions_user    ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_plan    ON subscriptions(plan_code);
CREATE INDEX idx_subscriptions_status  ON subscriptions(status);

-- Contrainte : 1 seule subscription trial/active par user à tout instant
CREATE UNIQUE INDEX uniq_user_active_sub
  ON subscriptions(user_id) WHERE status IN ('trial','active');

CREATE TRIGGER trg_subscriptions_updated_at
  BEFORE UPDATE ON subscriptions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Audit complet (D111) : table financière sensible
CREATE TRIGGER trg_audit_subscriptions
  AFTER INSERT OR UPDATE OR DELETE ON subscriptions
  FOR EACH ROW EXECUTE FUNCTION process_audit_log();

-- 13.3 Trigger auto-création subscription free à la création user (Opus fix #4)
-- Sans ce trigger, un user fraîchement inscrit n'a aucune sub → checks quota plantent
CREATE OR REPLACE FUNCTION create_default_subscription()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO subscriptions (user_id, plan_code, status)
  VALUES (NEW.id, 'free', 'active');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_create_default_subscription
  AFTER INSERT ON users
  FOR EACH ROW EXECUTE FUNCTION create_default_subscription();


-- ============================================================
-- RLS — ROW LEVEL SECURITY
-- ============================================================
-- Règle Postgres critique : ENABLE RLS + 0 policy = aucun accès
-- (sauf service_role qui bypass tout). Donc activer RLS et déclarer
-- les policies dans le même bloc.
-- ============================================================

-- ----------------------------------------------------------------
-- 1) Référentiel — lecture publique
-- ----------------------------------------------------------------
ALTER TABLE currencies            ENABLE ROW LEVEL SECURITY;
ALTER TABLE countries             ENABLE ROW LEVEL SECURITY;
ALTER TABLE sectors               ENABLE ROW LEVEL SECURITY;
ALTER TABLE subsectors            ENABLE ROW LEVEL SECURITY;
ALTER TABLE exchanges             ENABLE ROW LEVEL SECURITY;
ALTER TABLE instrument_types      ENABLE ROW LEVEL SECURITY;
ALTER TABLE instruments           ENABLE ROW LEVEL SECURITY;
ALTER TABLE currency_rate_presets ENABLE ROW LEVEL SECURITY;
ALTER TABLE ivi_variants          ENABLE ROW LEVEL SECURITY;

CREATE POLICY read_all ON currencies            FOR SELECT USING (true);
CREATE POLICY read_all ON countries             FOR SELECT USING (true);
CREATE POLICY read_all ON sectors               FOR SELECT USING (true);
CREATE POLICY read_all ON subsectors            FOR SELECT USING (true);
CREATE POLICY read_all ON exchanges             FOR SELECT USING (true);
CREATE POLICY read_all ON instrument_types      FOR SELECT USING (true);
CREATE POLICY read_all ON instruments           FOR SELECT USING (true);
CREATE POLICY read_all ON currency_rate_presets FOR SELECT USING (true);
CREATE POLICY read_all ON ivi_variants          FOR SELECT USING (true);

-- ----------------------------------------------------------------
-- 2) Données marché — lecture publique (gratuit V1, monétisé V2 via API)
-- ----------------------------------------------------------------
ALTER TABLE daily_candles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE intraday_snapshots      ENABLE ROW LEVEL SECURITY;
ALTER TABLE intraday_meta_data      ENABLE ROW LEVEL SECURITY;
ALTER TABLE intraday_chart_points   ENABLE ROW LEVEL SECURITY;
ALTER TABLE intraday_transactions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_book_levels       ENABLE ROW LEVEL SECURITY;
ALTER TABLE boc_documents           ENABLE ROW LEVEL SECURITY;
ALTER TABLE boc_embeddings          ENABLE ROW LEVEL SECURITY;
ALTER TABLE boc_instrument_mentions ENABLE ROW LEVEL SECURITY;

CREATE POLICY read_all ON daily_candles           FOR SELECT USING (true);
CREATE POLICY read_all ON intraday_snapshots      FOR SELECT USING (true);
CREATE POLICY read_all ON intraday_meta_data      FOR SELECT USING (true);
CREATE POLICY read_all ON intraday_chart_points   FOR SELECT USING (true);
CREATE POLICY read_all ON intraday_transactions   FOR SELECT USING (true);
CREATE POLICY read_all ON order_book_levels       FOR SELECT USING (true);
CREATE POLICY read_all ON boc_documents           FOR SELECT USING (true);
CREATE POLICY read_all ON boc_embeddings          FOR SELECT USING (true);
CREATE POLICY read_all ON boc_instrument_mentions FOR SELECT USING (true);

-- ----------------------------------------------------------------
-- 3) Profil utilisateur — own only (social features = V2)
-- ----------------------------------------------------------------
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY users_select_own ON users FOR SELECT USING (auth.uid() = id);
CREATE POLICY users_update_own ON users FOR UPDATE USING (auth.uid() = id);
-- INSERT/DELETE pilotés par le trigger Supabase Auth (service_role)

-- ----------------------------------------------------------------
-- 4) Données user "own only"
-- ----------------------------------------------------------------
ALTER TABLE user_exchange_rates        ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_instrument_flags      ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_preferences           ENABLE ROW LEVEL SECURITY;
ALTER TABLE chart_templates            ENABLE ROW LEVEL SECURITY;
ALTER TABLE chart_drawings             ENABLE ROW LEVEL SECURITY;
ALTER TABLE indicator_preferences      ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_rules                ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_notification_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE ivi_conversations          ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_metrics             ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_all ON user_exchange_rates        FOR ALL USING (auth.uid() = user_id);
CREATE POLICY own_all ON user_instrument_flags      FOR ALL USING (auth.uid() = user_id);
CREATE POLICY own_all ON user_preferences           FOR ALL USING (auth.uid() = user_id);
CREATE POLICY own_all ON chart_templates            FOR ALL USING (auth.uid() = user_id);
CREATE POLICY own_all ON chart_drawings             FOR ALL USING (auth.uid() = user_id);
CREATE POLICY own_all ON indicator_preferences      FOR ALL USING (auth.uid() = user_id);
CREATE POLICY own_all ON alert_rules                FOR ALL USING (auth.uid() = user_id);
CREATE POLICY own_all ON user_notification_settings FOR ALL USING (auth.uid() = user_id);
CREATE POLICY own_all ON ivi_conversations          FOR ALL USING (auth.uid() = user_id);
CREATE POLICY own_all ON custom_metrics             FOR ALL USING (auth.uid() = user_id);

-- ----------------------------------------------------------------
-- 5) Données user "own + public" (flag is_public sur la ligne)
-- ----------------------------------------------------------------
ALTER TABLE watchlists         ENABLE ROW LEVEL SECURITY;
ALTER TABLE portfolios         ENABLE ROW LEVEL SECURITY;
ALTER TABLE screener_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_all      ON watchlists         FOR ALL    USING (auth.uid() = user_id);
CREATE POLICY public_read  ON watchlists         FOR SELECT USING (is_public = true);
CREATE POLICY own_all      ON portfolios         FOR ALL    USING (auth.uid() = user_id);
CREATE POLICY public_read  ON portfolios         FOR SELECT USING (is_public = true);
CREATE POLICY own_all      ON screener_templates FOR ALL    USING (auth.uid() = user_id);
CREATE POLICY public_read  ON screener_templates FOR SELECT USING (is_public = true);

-- ----------------------------------------------------------------
-- 6) Données user accessibles via parent (EXISTS)
-- ----------------------------------------------------------------
ALTER TABLE watchlist_items         ENABLE ROW LEVEL SECURITY;
ALTER TABLE positions               ENABLE ROW LEVEL SECURITY;
ALTER TABLE portfolio_transactions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE portfolio_snapshots     ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_notifications     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ivi_messages            ENABLE ROW LEVEL SECURITY;
ALTER TABLE ivi_message_edits       ENABLE ROW LEVEL SECURITY;
ALTER TABLE ivi_message_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ivi_actions             ENABLE ROW LEVEL SECURITY;

-- watchlist_items via watchlist
CREATE POLICY own_all ON watchlist_items FOR ALL
  USING (EXISTS (SELECT 1 FROM watchlists w
                 WHERE w.id = watchlist_items.watchlist_id AND w.user_id = auth.uid()));
CREATE POLICY public_read ON watchlist_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM watchlists w
                 WHERE w.id = watchlist_items.watchlist_id AND w.is_public = true));

-- positions / portfolio_transactions / portfolio_snapshots via portfolio
CREATE POLICY own_all ON positions FOR ALL
  USING (EXISTS (SELECT 1 FROM portfolios p
                 WHERE p.id = positions.portfolio_id AND p.user_id = auth.uid()));
CREATE POLICY public_read ON positions FOR SELECT
  USING (EXISTS (SELECT 1 FROM portfolios p
                 WHERE p.id = positions.portfolio_id AND p.is_public = true));

CREATE POLICY own_all ON portfolio_transactions FOR ALL
  USING (EXISTS (SELECT 1 FROM portfolios p
                 WHERE p.id = portfolio_transactions.portfolio_id AND p.user_id = auth.uid()));
-- Pas de public_read sur tx (montants sensibles)

CREATE POLICY own_all ON portfolio_snapshots FOR ALL
  USING (EXISTS (SELECT 1 FROM portfolios p
                 WHERE p.id = portfolio_snapshots.portfolio_id AND p.user_id = auth.uid()));
CREATE POLICY public_read ON portfolio_snapshots FOR SELECT
  USING (EXISTS (SELECT 1 FROM portfolios p
                 WHERE p.id = portfolio_snapshots.portfolio_id AND p.is_public = true));

-- alert_notifications via alert_rule (read-only pour user, écrit par worker)
CREATE POLICY own_read ON alert_notifications FOR SELECT
  USING (EXISTS (SELECT 1 FROM alert_rules r
                 WHERE r.id = alert_notifications.rule_id AND r.user_id = auth.uid()));

-- ivi_messages / edits / attachments / actions via conversation
CREATE POLICY own_all ON ivi_messages FOR ALL
  USING (EXISTS (SELECT 1 FROM ivi_conversations c
                 WHERE c.id = ivi_messages.conversation_id AND c.user_id = auth.uid()));

CREATE POLICY own_all ON ivi_message_edits FOR ALL
  USING (EXISTS (SELECT 1 FROM ivi_messages m
                 JOIN ivi_conversations c ON c.id = m.conversation_id
                 WHERE m.id = ivi_message_edits.message_id AND c.user_id = auth.uid()));

CREATE POLICY own_all ON ivi_message_attachments FOR ALL
  USING (EXISTS (SELECT 1 FROM ivi_messages m
                 JOIN ivi_conversations c ON c.id = m.conversation_id
                 WHERE m.id = ivi_message_attachments.message_id AND c.user_id = auth.uid()));

CREATE POLICY own_all ON ivi_actions FOR ALL
  USING (EXISTS (SELECT 1 FROM ivi_messages m
                 JOIN ivi_conversations c ON c.id = m.conversation_id
                 WHERE m.id = ivi_actions.message_id AND c.user_id = auth.uid()));

-- ----------------------------------------------------------------
-- 7) Plateforme — lecture publique + écriture own
-- ----------------------------------------------------------------
ALTER TABLE feature_proposals    ENABLE ROW LEVEL SECURITY;
ALTER TABLE proposal_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE proposal_votes       ENABLE ROW LEVEL SECURITY;

CREATE POLICY read_all          ON feature_proposals FOR SELECT USING (true);
CREATE POLICY own_insert        ON feature_proposals FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY own_update        ON feature_proposals FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY own_delete        ON feature_proposals FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY read_all ON proposal_attachments FOR SELECT USING (true);
CREATE POLICY own_write ON proposal_attachments FOR ALL
  USING (EXISTS (SELECT 1 FROM feature_proposals p
                 WHERE p.id = proposal_attachments.proposal_id AND p.user_id = auth.uid()));

CREATE POLICY read_all   ON proposal_votes FOR SELECT USING (true);
CREATE POLICY own_insert ON proposal_votes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY own_delete ON proposal_votes FOR DELETE USING (auth.uid() = user_id);

-- ----------------------------------------------------------------
-- 8) Zone 4 Fondamentaux — lecture publique (data marché)
-- ----------------------------------------------------------------
ALTER TABLE dividends         ENABLE ROW LEVEL SECURITY;
ALTER TABLE corporate_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY read_all ON dividends         FOR SELECT USING (true);
CREATE POLICY read_all ON corporate_actions FOR SELECT USING (true);

-- ----------------------------------------------------------------
-- 9) Zone 12 News & Macro — lecture publique
-- ----------------------------------------------------------------
ALTER TABLE news_sources              ENABLE ROW LEVEL SECURITY;
ALTER TABLE news_articles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE news_article_instruments  ENABLE ROW LEVEL SECURITY;
ALTER TABLE economic_indicators       ENABLE ROW LEVEL SECURITY;

CREATE POLICY read_all ON news_sources             FOR SELECT USING (true);
CREATE POLICY read_all ON news_articles            FOR SELECT USING (true);
CREATE POLICY read_all ON news_article_instruments FOR SELECT USING (true);
CREATE POLICY read_all ON economic_indicators      FOR SELECT USING (true);

-- ----------------------------------------------------------------
-- 10) audit_logs — admin only (pas de SELECT public)
-- ----------------------------------------------------------------
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
-- Aucune policy SELECT : seul service_role peut lire. À ajouter plus tard si besoin admin via JWT.

-- ----------------------------------------------------------------
-- 11) Zone 13 Subscriptions — plans publics, subs personnelles
-- ----------------------------------------------------------------
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions      ENABLE ROW LEVEL SECURITY;

CREATE POLICY read_all  ON subscription_plans FOR SELECT USING (true);
CREATE POLICY own_read  ON subscriptions      FOR SELECT USING (auth.uid() = user_id);
-- Pas de policy INSERT/UPDATE/DELETE : service_role uniquement (via API ou trigger).
-- Un user ne crée/modifie pas directement sa subscription (passage par paiement API).


-- ============================================================
-- FIN DU SCHÉMA
-- ============================================================
-- Reste à faire après chargement des données :
-- 1. Index ivfflat sur boc_embeddings.embedding (cf. ZONE 10)
-- 2. Zone 4 : financial_metrics (4.3) + financial_reports (4.4) à compléter
-- ============================================================

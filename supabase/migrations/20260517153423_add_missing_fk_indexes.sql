-- ============================================================
-- D129 — Index FK manquants (réponse Supabase Performance Advisor)
-- ============================================================
-- 11 FK identifiées sans index :
--   - PK composites où la FK n'est pas la première colonne
--     (PK couvre seulement la 1ère col pour lookup)
--   - FK simples oubliées (currencies, instruments, watchlists)
-- ============================================================

-- chart_drawings PK = (user_id, instrument_id, timeframe) → instrument_id non couvert
CREATE INDEX idx_chart_drawings_instrument ON chart_drawings(instrument_id);

-- positions PK = (portfolio_id, instrument_id) → instrument_id non couvert
CREATE INDEX idx_positions_instrument ON positions(instrument_id);

-- user_instrument_flags PK = (user_id, instrument_id) → instrument_id non couvert
CREATE INDEX idx_user_instrument_flags_instrument ON user_instrument_flags(instrument_id);

-- watchlist_items PK = (watchlist_id, instrument_id) → instrument_id non couvert
CREATE INDEX idx_watchlist_items_instrument ON watchlist_items(instrument_id);

-- feature_proposals.user_id : FK simple oubliée
CREATE INDEX idx_feature_proposals_user ON feature_proposals(user_id);

-- portfolios.base_currency : FK simple oubliée
CREATE INDEX idx_portfolios_base_currency ON portfolios(base_currency);

-- user_exchange_rates : 3 FK supplémentaires (idx_user_rates_user existe déjà)
CREATE INDEX idx_user_exchange_rates_from_currency ON user_exchange_rates(from_currency);
CREATE INDEX idx_user_exchange_rates_to_currency   ON user_exchange_rates(to_currency);
CREATE INDEX idx_user_exchange_rates_preset        ON user_exchange_rates(preset_code);

-- user_preferences : 2 FK additionnelles
CREATE INDEX idx_user_preferences_default_currency
  ON user_preferences(default_currency)
  WHERE default_currency IS NOT NULL;
CREATE INDEX idx_user_preferences_default_watchlist
  ON user_preferences(default_watchlist_id)
  WHERE default_watchlist_id IS NOT NULL;

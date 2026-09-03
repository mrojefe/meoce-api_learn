-- Bascule d'UT granulaire lente (2026-08-12, JF) : get_intraday_tick_candles trie
-- TOUT l'historique filtré (jusqu'à 369k lignes) par `ORDER BY trade_timestamp, seq`
-- à chaque appel (row_number() OVER, dans 20260809140000_intraday_candles_date_range.sql).
-- Le seul index existant (idx_tx_instr_date, ordre market_date DESC, trade_timestamp DESC)
-- ne correspond pas à cet ordre de tri (ASC, sans market_date) : tri complet à chaque appel.
CREATE INDEX IF NOT EXISTS idx_tx_instr_ts_seq
  ON intraday_transactions (instrument_id, trade_timestamp, seq);

-- Ajoute un rang de séquence aux transactions intraday pour distinguer les
-- exécutions multiples tombant à la même milliseconde (SGI-AGI en envoie
-- réellement plusieurs par jour, jusqu'à 3 trades identiques constatés le
-- 2026-07-16, cf. BD_THINKNG/intraday_thought.md — Annexe table 3 + Table 4).
-- L'ancienne clé UNIQUE (instrument_id, trade_timestamp) en perdait
-- silencieusement une partie ; on ne peut plus jamais perdre un trade réel.

ALTER TABLE intraday_transactions
  ADD COLUMN IF NOT EXISTS seq int NOT NULL DEFAULT 0;

ALTER TABLE intraday_transactions
  DROP CONSTRAINT IF EXISTS intraday_transactions_instrument_id_trade_timestamp_key;

ALTER TABLE intraday_transactions
  ADD CONSTRAINT intraday_transactions_instr_ts_seq_key
  UNIQUE (instrument_id, trade_timestamp, seq);

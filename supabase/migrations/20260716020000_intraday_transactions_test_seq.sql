-- Applique sur intraday_transactions_test le même correctif que
-- 20260716010000 (prod) — oublié initialement, trouvé par l'agent de
-- vérification pré-ouverture du 2026-07-16 : la migration seq n'avait été
-- appliquée qu'à la table prod, pas à la table de test.

ALTER TABLE intraday_transactions_test
  ADD COLUMN IF NOT EXISTS seq int NOT NULL DEFAULT 0;

ALTER TABLE intraday_transactions_test
  ADD CONSTRAINT intraday_transactions_test_instr_ts_seq_key
  UNIQUE (instrument_id, trade_timestamp, seq);

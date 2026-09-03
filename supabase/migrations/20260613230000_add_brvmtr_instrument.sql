-- Ajout de l'indice BRVM Composite Total Return (BRVMTR)
-- Apparu dans les BOC BRVM à partir de janvier 2026.
-- 109 points historiques disponibles dans GOLD_indices_eod.json (2026-01-02 → 2026-06-12).

INSERT INTO instruments (symbol, name, type, status, currency_code, exchange_id, sector_id, country_code, created_at)
VALUES ('BRVMTR', 'BRVM Composite Total Return', 'index', 'active', 'XOF', 1, 7, 'CI', now());

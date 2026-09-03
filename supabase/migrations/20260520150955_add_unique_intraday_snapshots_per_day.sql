-- Migration : intraday_snapshots → 1 ligne par instrument par jour (dernière valeur)
--
-- Avant : INSERT à chaque scrape → N lignes/instrument/jour (1 toutes les 2 min)
-- Après : UPSERT sur (instrument_id, market_date) → toujours la dernière valeur connue
--
-- Étape 1 : supprimer les doublons existants (garder le plus récent par instrument+date)
DELETE FROM intraday_snapshots a
USING intraday_snapshots b
WHERE a.instrument_id = b.instrument_id
  AND a.market_date   = b.market_date
  AND a.scraped_at    < b.scraped_at;

-- Étape 2 : ajouter la contrainte UNIQUE pour permettre le UPSERT côté worker
ALTER TABLE intraday_snapshots
  ADD CONSTRAINT uq_intraday_snapshots_instr_date
  UNIQUE (instrument_id, market_date);

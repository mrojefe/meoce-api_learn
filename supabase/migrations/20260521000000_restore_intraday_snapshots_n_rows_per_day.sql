-- Restaure D42 : intraday_snapshots = N lignes/jour (1 par scrape)
--
-- La migration 20260520150955 avait ajouté UNIQUE(instrument_id, market_date)
-- et supprimé les doublons → 1 ligne/jour seulement.
-- D42 + MLD original spécifient : UNIQUE(instrument_id, scraped_at),
-- chaque scrape crée une nouvelle ligne → historique intra-jour préservé.
--
-- La contrainte UNIQUE(instrument_id, scraped_at) existe déjà dans le schema
-- initial ; on supprime uniquement la contrainte erronée 1-ligne/jour.

ALTER TABLE intraday_snapshots
  DROP CONSTRAINT IF EXISTS uq_intraday_snapshots_instr_date;

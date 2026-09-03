-- ============================================================
-- Migration : Fix contraintes UNIQUE manquantes sur tables intraday
-- Date      : 2026-06-08
-- Problème  : workers intraday échouent avec :
--             "there is no unique or exclusion constraint matching the ON CONFLICT specification"
--
-- Cause :
--   20260520 → ajoute UNIQUE(instrument_id, market_date) sur intraday_snapshots
--   20260521 → supprime cette contrainte (revient à N lignes/jour)
--   Résultat : UNIQUE(instrument_id, scraped_at) du schéma initial a peut-être
--              été supprimée dans la chaîne de DROP CONSTRAINT.
--
-- Ce fichier :
--   1. Restaure UNIQUE(instrument_id, scraped_at) sur intraday_snapshots
--   2. Vérifie/ajoute UNIQUE(instrument_id, timestamp_ms) sur intraday_chart_points
--   3. Vérifie/ajoute UNIQUE(instrument_id, trade_timestamp) sur intraday_transactions
--   4. Vérifie UNIQUE(instrument_id, market_date) sur intraday_meta_data
--   5. Vérifie PK(instrument_id, market_date, carnet_hash, rank) sur order_book_levels
--   Toutes les contraintes utilisent IF NOT EXISTS pour être idempotentes.
-- ============================================================

-- ============================================================
-- 1. intraday_snapshots
--    Worker cible : on_conflict="instrument_id,scraped_at"
--    = N lignes par jour (1 par scrape, D42)
-- ============================================================

-- Supprimer toute contrainte 1-ligne/jour résiduelle (par sécurité)
ALTER TABLE intraday_snapshots
  DROP CONSTRAINT IF EXISTS uq_intraday_snapshots_instr_date;

-- Recréer UNIQUE(instrument_id, scraped_at) si elle a disparu
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'intraday_snapshots'::regclass
      AND contype = 'u'
      AND conname LIKE '%scraped_at%'
  ) THEN
    ALTER TABLE intraday_snapshots
      ADD CONSTRAINT uq_intraday_snapshots_instr_scrapedat
      UNIQUE (instrument_id, scraped_at);
    RAISE NOTICE 'CREATED: uq_intraday_snapshots_instr_scrapedat';
  ELSE
    RAISE NOTICE 'OK (already exists): UNIQUE(instrument_id, scraped_at) on intraday_snapshots';
  END IF;
END;
$$;

-- ============================================================
-- 2. intraday_chart_points
--    Worker cible : on_conflict="instrument_id,timestamp_ms"
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'intraday_chart_points'::regclass
      AND contype = 'u'
      AND conname LIKE '%timestamp_ms%'
  ) THEN
    ALTER TABLE intraday_chart_points
      ADD CONSTRAINT uq_intraday_chart_points_instr_ts
      UNIQUE (instrument_id, timestamp_ms);
    RAISE NOTICE 'CREATED: uq_intraday_chart_points_instr_ts';
  ELSE
    RAISE NOTICE 'OK (already exists): UNIQUE(instrument_id, timestamp_ms) on intraday_chart_points';
  END IF;
END;
$$;

-- ============================================================
-- 3. intraday_transactions
--    Worker cible : on_conflict="instrument_id,trade_timestamp"
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'intraday_transactions'::regclass
      AND contype = 'u'
      AND conname LIKE '%trade_timestamp%'
  ) THEN
    ALTER TABLE intraday_transactions
      ADD CONSTRAINT uq_intraday_transactions_instr_ts
      UNIQUE (instrument_id, trade_timestamp);
    RAISE NOTICE 'CREATED: uq_intraday_transactions_instr_ts';
  ELSE
    RAISE NOTICE 'OK (already exists): UNIQUE(instrument_id, trade_timestamp) on intraday_transactions';
  END IF;
END;
$$;

-- ============================================================
-- 4. intraday_meta_data
--    Worker cible : on_conflict="instrument_id,market_date"
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'intraday_meta_data'::regclass
      AND (contype = 'u' OR contype = 'p')
      AND conname LIKE '%market_date%'
  ) THEN
    ALTER TABLE intraday_meta_data
      ADD CONSTRAINT uq_intraday_meta_data_instr_date
      UNIQUE (instrument_id, market_date);
    RAISE NOTICE 'CREATED: uq_intraday_meta_data_instr_date';
  ELSE
    RAISE NOTICE 'OK (already exists): UNIQUE(instrument_id, market_date) on intraday_meta_data';
  END IF;
END;
$$;

-- ============================================================
-- 5. order_book_levels
--    Worker cible : on_conflict="instrument_id,market_date,carnet_hash,rank"
--    = PK composite (devrait déjà exister depuis le schéma initial)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'order_book_levels'::regclass
      AND contype = 'p'
  ) THEN
    ALTER TABLE order_book_levels
      ADD PRIMARY KEY (instrument_id, market_date, carnet_hash, rank);
    RAISE NOTICE 'CREATED: PRIMARY KEY on order_book_levels';
  ELSE
    RAISE NOTICE 'OK (already exists): PRIMARY KEY on order_book_levels';
  END IF;
END;
$$;

-- ============================================================
-- VÉRIFICATION FINALE — affiche toutes les contraintes intraday
-- ============================================================
SELECT
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema   = kcu.table_schema
WHERE tc.table_schema = 'public'
  AND tc.table_name IN (
    'intraday_snapshots',
    'intraday_chart_points',
    'intraday_transactions',
    'order_book_levels',
    'intraday_meta_data'
  )
  AND tc.constraint_type IN ('UNIQUE', 'PRIMARY KEY')
GROUP BY tc.table_name, tc.constraint_name, tc.constraint_type
ORDER BY tc.table_name, tc.constraint_type;

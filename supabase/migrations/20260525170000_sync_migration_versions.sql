-- Migration: Resynchronisation des versions schema_migrations
-- Contexte : les migrations appliquées via MCP reçoivent un timestamp d'application
-- (heure réelle) au lieu du timestamp du fichier local. Le CLI Supabase ne reconnaît
-- donc pas ces fichiers locaux comme "déjà appliqués" et tenterait de les ré-exécuter.
-- Solution : enregistrer les versions locales manquantes sans ré-exécuter le SQL.

INSERT INTO supabase_migrations.schema_migrations (version) VALUES
  ('20260520150955'),  -- add_unique_intraday_snapshots_per_day   → appliquée comme 20260520151431
  ('20260521000000'),  -- restore_intraday_snapshots_n_rows_per_day → appliquée comme 20260521161620
  ('20260525120000'),  -- create_daily_order_book                  → appliquée comme 20260525161953
  ('20260525140000'),  -- update_brvm_sectors                      → appliquée comme 20260525165046
  ('20260525160000')   -- normalize_sector_names                   → appliquée comme 20260525165837
ON CONFLICT (version) DO NOTHING;

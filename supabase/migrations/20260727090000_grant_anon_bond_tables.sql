-- Corrige un trou de permissions préexistant : `bond_details`/`bond_candles`
-- ont bien une policy RLS `read_all USING (true)` depuis leur création
-- (20260529200000_afriview_v2_schema_extensions.sql) mais le GRANT SELECT au
-- rôle `anon`/`authenticated` n'a jamais été fait — la RLS ne dispense pas du
-- GRANT Postgres de base, elle ne fait que restreindre les LIGNES visibles.
-- Résultat : `SELECT * FROM bond_details` échouait avec
-- "permission denied for table bond_details" (42501), rendant tout écran
-- obligations vide/cassé malgré des données réelles en base (découvert en
-- branchant l'écran Obligations du Screener, 2026-07-27).
GRANT SELECT ON public.bond_details TO anon, authenticated;
GRANT SELECT ON public.bond_candles TO anon, authenticated;

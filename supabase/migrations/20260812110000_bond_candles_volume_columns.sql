-- Colonnes volume_titre/volume_valeur documentées dans une migration antérieure
-- (20260529200000_afriview_v2_schema_extensions.sql) mais jamais réellement
-- appliquées sur bond_candles — découvert en incident (2026-08-12, staging) :
-- toute requête d'historique sur une obligation échouait en boucle
-- (42703 column bond_candles.volume_titre does not exist) dès le déploiement
-- du fix worker_obligations_cotation.py qui les écrit désormais. Additive,
-- IF NOT EXISTS : sûr à rejouer même là où les colonnes existent déjà.
ALTER TABLE bond_candles
  ADD COLUMN IF NOT EXISTS volume_titre BIGINT CHECK (volume_titre IS NULL OR volume_titre >= 0),
  ADD COLUMN IF NOT EXISTS volume_valeur NUMERIC(18,2);

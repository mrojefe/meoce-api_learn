-- Ajoute les colonnes "brutes" (non ajustées aux splits) en miroir des colonnes
-- existantes (déjà ajustées), sur le modèle de Richbourse (cours_ajuste vs
-- cours_normal / volume_ajuste vs volume_normal).
--
-- daily_candles : colonnes existantes = déjà ajustées (vérifié 100% vs
--   Richbourse). On ajoute les colonnes _brut pour le prix réel historique.
-- daily_volume : colonne "quantity" existante = déjà brute (vérifié 99.9% vs
--   Richbourse volume_normal). On ajoute quantity_brut comme copie de
--   référence AVANT de corriger "quantity" pour qu'il devienne la version
--   ajustée (cohérente avec le prix, pour usage backtest par défaut).
--
-- Aucun backfill de valeurs ici — uniquement le changement de schéma.
-- Le backfill (calcul des ratios par symbole/régime) est fait séparément
-- via script, pas dans cette migration.

ALTER TABLE public.daily_candles
  ADD COLUMN IF NOT EXISTS open_price_brut  numeric,
  ADD COLUMN IF NOT EXISTS high_price_brut  numeric,
  ADD COLUMN IF NOT EXISTS low_price_brut   numeric,
  ADD COLUMN IF NOT EXISTS close_price_brut numeric;

ALTER TABLE public.daily_volume
  ADD COLUMN IF NOT EXISTS quantity_brut bigint;

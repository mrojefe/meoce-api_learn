-- Migration pour supprimer les anciens indices sectoriels obsolètes de la BRVM
-- (Avant la réforme de 2023) ainsi que les indices spécifiques à des plateformes tierces.

-- Grâce au ON DELETE CASCADE sur daily_volume et daily_candles,
-- la suppression de l'instrument supprimera automatiquement ses données historiques.

DELETE FROM public.instruments
WHERE symbol IN (
    'BRVMAG', -- BRVM Agriculture
    'BRVMAS', -- BRVM Autres Secteurs
    'BRVMDI', -- BRVM Distribution
    'BRVMFI', -- BRVM Finance
    'BRVMTR', -- BRVM Transport
    'BRVM-D', -- BRVM Development Index
    'BRVM-E', -- BRVM Issuers Index
    'BRVM-N', -- BRVM New Listings Index
    'SIKATR'  -- Sika Total Return (non officiel)
);

-- Note concernant les doublons (Tu pourras décommenter si tu souhaites les nettoyer) :
-- Il y a des doublons pour certains indices généraux : 
-- BRVM30 (actif) vs BRVM-30 (inactif)
-- BRVMC (actif) vs BRVM-C (inactif)
-- BRVMIN (actif) vs BRVM-IN (actif)
/*
DELETE FROM public.instruments WHERE symbol IN ('BRVM-30', 'BRVM-C');
*/

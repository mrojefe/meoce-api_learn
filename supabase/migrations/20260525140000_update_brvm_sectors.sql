-- Migration: Mise à jour classification sectorielle BRVM
-- Aligne la table sectors sur la nomenclature officielle BRVM actuelle (majuscules)
-- Ajoute 2 secteurs manquants : CONSOMMATION_DE_BASE et ENERGIE
-- Reclasse 17 instruments selon la nouvelle classification BRVM (source : BOC M7 2022+)

-- ─── ÉTAPE 1 : Renommer les secteurs existants (noms officiels BRVM, majuscules) ─────
UPDATE sectors SET name = 'SERVICES_FINANCIERS',         description = 'BRVM - SERVICES FINANCIERS'          WHERE name = 'finance';
UPDATE sectors SET name = 'INDUSTRIELS',                  description = 'BRVM - INDUSTRIELS'                   WHERE name = 'industrie';
UPDATE sectors SET name = 'AGRICULTURE',                  description = 'BRVM - AGRICULTURE'                   WHERE name = 'agriculture';
UPDATE sectors SET name = 'DISTRIBUTION',                 description = 'BRVM - DISTRIBUTION'                  WHERE name = 'distribution';
UPDATE sectors SET name = 'SERVICES_PUBLICS',             description = 'BRVM - SERVICES PUBLICS'              WHERE name = 'services_publics';
UPDATE sectors SET name = 'TRANSPORT',                    description = 'BRVM - TRANSPORT'                     WHERE name = 'transport';
UPDATE sectors SET name = 'AUTRES',                       description = 'BRVM - AUTRES'                        WHERE name = 'autres';
UPDATE sectors SET name = 'TELECOMMUNICATIONS',           description = 'BRVM - TELECOMMUNICATIONS'            WHERE name = 'telecommunications';
UPDATE sectors SET name = 'CONSOMMATION_DISCRETIONNAIRE', description = 'BRVM - CONSOMMATION DISCRETIONNAIRE'  WHERE name = 'consumer_discretionary';

-- ─── ÉTAPE 2 : Ajouter les 2 secteurs manquants ─────────────────────────────────────
INSERT INTO sectors (name, description) VALUES
  ('CONSOMMATION_DE_BASE', 'BRVM - CONSOMMATION DE BASE'),
  ('ENERGIE',              'BRVM - ENERGIE');

-- ─── ÉTAPE 3 : Reclasser les instruments selon nouvelle classification BRVM ─────────

-- CONSOMMATION_DE_BASE (9 instruments) : ex-agriculture + ex-industrie
-- NTLC, SLBC, STBC, UNLC (ex-industrie) + PALC, SCRC, SICC, SOGC, SPHC (ex-agriculture)
UPDATE instruments
SET sector_id = (SELECT id FROM sectors WHERE name = 'CONSOMMATION_DE_BASE')
WHERE symbol IN ('NTLC', 'PALC', 'SCRC', 'SICC', 'SLBC', 'SOGC', 'SPHC', 'STBC', 'UNLC');

-- ENERGIE (4 instruments) : ex-distribution (SHEC, TTLC, TTLS) + ex-industrie (SMBC)
UPDATE instruments
SET sector_id = (SELECT id FROM sectors WHERE name = 'ENERGIE')
WHERE symbol IN ('SHEC', 'SMBC', 'TTLC', 'TTLS');

-- CONSOMMATION_DISCRETIONNAIRE (6 instruments)
-- ex-distribution : ABJC, BNBC, CFAC, PRSC
-- ex-industrie    : NEIC, UNXC
UPDATE instruments
SET sector_id = (SELECT id FROM sectors WHERE name = 'CONSOMMATION_DISCRETIONNAIRE')
WHERE symbol IN ('ABJC', 'BNBC', 'CFAC', 'NEIC', 'PRSC', 'UNXC');

-- INDUSTRIELS (3 instruments)
-- ex-transport : SDSC (Africa Global Logistics), SVOC (Movis)
-- ex-autres    : STAC (SETAO CI)
UPDATE instruments
SET sector_id = (SELECT id FROM sectors WHERE name = 'INDUSTRIELS')
WHERE symbol IN ('SDSC', 'SVOC', 'STAC');

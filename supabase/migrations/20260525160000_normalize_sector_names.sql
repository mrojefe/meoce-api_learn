-- Migration: Harmonisation noms + codes secteurs BRVM
-- 1. Uniformiser les noms : MAJUSCULES + ESPACES (nomenclature BRVM officielle)
-- 2. TRANSPORTS → TRANSPORT (correction pluriel)
-- 3. Ajouter codes BRVM manquants : CB et ENE
-- 4. Compléter descriptions NULL pour les 4 secteurs renommés manuellement

-- ─── Descriptions manquantes (4 secteurs renommés manuellement) ──────────────
UPDATE sectors SET description = 'BRVM - SERVICES FINANCIERS'
  WHERE name = 'SERVICES FINANCIERS';

UPDATE sectors SET description = 'BRVM - SERVICES PUBLICS'
  WHERE name = 'SERVICES PUBLICS';

UPDATE sectors SET description = 'BRVM - TELECOMMUNICATIONS'
  WHERE name = 'TELECOMMUNICATIONS';

-- ─── TRANSPORTS → TRANSPORT (correction pluriel + description) ────────────────
UPDATE sectors SET name = 'TRANSPORT', description = 'BRVM - TRANSPORT'
  WHERE name = 'TRANSPORTS';

-- ─── Underscores → espaces (secteurs de la migration 20260525140000) ──────────
UPDATE sectors SET name = 'CONSOMMATION DE BASE'
  WHERE name = 'CONSOMMATION_DE_BASE';

UPDATE sectors SET name = 'CONSOMMATION DISCRETIONNAIRE'
  WHERE name = 'CONSOMMATION_DISCRETIONNAIRE';

-- ─── Codes BRVM manquants ─────────────────────────────────────────────────────
UPDATE sectors SET code = 'CB'  WHERE name = 'CONSOMMATION DE BASE';
UPDATE sectors SET code = 'ENE' WHERE name = 'ENERGIE';

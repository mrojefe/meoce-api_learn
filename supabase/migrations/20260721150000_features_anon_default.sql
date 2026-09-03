-- ============================================================================
-- features.anon_default — le palier VISITEUR devient réglable EN BASE
--
-- Constat de l'audit (2026-07-21) :
--   • `features.free_default` (14 clés) et `subscription_plans.features` sont bien en
--     base… mais le FRONTEND garde une COPIE codée en dur (entitlementsStore.FREE_DEFAULTS),
--     avec une divergence réelle (cf. realtime_candle plus bas).
--   • Le palier VISITEUR (anon) n'existe NULLE PART en base : il est uniquement dans le
--     code serveur (`data-tier.ts`, DataTier = 'anon' | 'free' | 'pro'). Impossible de
--     l'ajuster sans redéployer.
--
-- Cette migration ajoute `anon_default`, initialisé À L'IDENTIQUE de `free_default` :
-- AUCUN changement de comportement immédiat, mais le palier visiteur devient réglable
-- par un simple UPDATE, comme le reste.
--
-- Idempotente. Aucune ligne utilisateur touchée (table de référence uniquement).
-- ============================================================================

ALTER TABLE features ADD COLUMN IF NOT EXISTS anon_default JSONB;

-- Seed : visiteur = free tant que JF n'en décide pas autrement (zéro régression).
UPDATE features SET anon_default = free_default WHERE anon_default IS NULL;

ALTER TABLE features ALTER COLUMN anon_default SET DEFAULT 'false'::jsonb;

COMMENT ON COLUMN features.anon_default IS
  'Valeur du droit pour un VISITEUR non connecté. Initialisée = free_default ; ajustable sans déploiement.';

-- ── Divergence corrigée : realtime_candle ───────────────────────────────────
-- La base disait `false`, mais l''application appliquait `true` pour les visiteurs via
-- la constante codée en dur du frontend — un VISITEUR avait donc la bougie live et un
-- inscrit GRATUIT ne l''avait pas (l''API renvoyant le free_default de la base écrase la
-- constante côté client). C''est l''inverse de l''intention produit documentée dans
-- entitlementsStore : « Bougie LIVE ouverte à TOUS, visiteurs compris — choix produit
-- assumé... l''hameçon d''acquisition ». Le moat reste la PROFONDEUR (history_years_max,
-- live_history_days), bornée par ailleurs côté serveur.
-- On aligne donc la base sur le comportement voulu. Pour revenir en arrière :
--   UPDATE features SET free_default='false'::jsonb, anon_default='false'::jsonb
--   WHERE key='realtime_candle';
UPDATE features
   SET free_default = 'true'::jsonb,
       anon_default = 'true'::jsonb
 WHERE key = 'realtime_candle';

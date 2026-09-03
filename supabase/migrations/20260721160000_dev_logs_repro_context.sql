-- ============================================================================
-- dev_logs : métadonnées de REPRODUCTION (demande JF 2026-07-21)
--
-- « tu prendras bien TOUTES LES MÉTADONNÉES de l'user (ip, appareil…) pour qu'on
--   puisse reproduire les bugs en local en cas de problème »
--
-- Aujourd'hui on ne garde que user_agent + url + session_id : insuffisant pour rejouer
-- un bug fidèlement. Il manque notamment la TAILLE D'ÉCRAN (la plupart des bugs de
-- cadrage/responsive en dépendent), le THÈME actif, le PALIER du compte (visiteur/free/
-- pro — beaucoup de bugs n'existent que pour un palier), le fuseau horaire, la langue,
-- le type de connexion, et l'IP (côté serveur uniquement, jamais envoyée par le client).
--
-- Idempotente. Table d'observabilité uniquement (aucune donnée métier).
-- ============================================================================

ALTER TABLE dev_logs ADD COLUMN IF NOT EXISTS ip TEXT;
ALTER TABLE dev_logs ADD COLUMN IF NOT EXISTS context JSONB;

COMMENT ON COLUMN dev_logs.ip IS
  'IP source, résolue CÔTÉ SERVEUR depuis les en-têtes (jamais fournie par le client).';
COMMENT ON COLUMN dev_logs.context IS
  'Contexte de reproduction : viewport, dpr, thème, palier du compte, timezone, langue, connexion, plateforme.';

-- Recherche par session (rejouer une session complète) et par IP (corréler des rapports).
CREATE INDEX IF NOT EXISTS idx_dev_logs_session_ts ON dev_logs (session_id, ts DESC);

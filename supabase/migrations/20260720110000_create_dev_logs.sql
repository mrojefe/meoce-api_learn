-- Observabilité dev (#166) : logs techniques détaillés (rendu graphe, UX,
-- réseau), activés UNIQUEMENT hors production, écrits par l'endpoint
-- POST /api/dev/logs en service_role (bypass RLS). Ce ne sont PAS des
-- données utilisateur sensibles -- traces techniques uniquement.
--
-- 3 canaux (A/B/C) : 'chart' (rendu graphe), 'ux' (parcours), 'net' (réseau).
--
-- RLS activée, AUCUNE policy anon/authenticated : lecture et écriture
-- refusées à ces deux rôles, seul service_role (bypass RLS) peut écrire/lire.
-- L'analyse se fait en SQL direct (psql), pas via PostgREST public.
--
-- Rétention : cette table peut grossir vite en dev/preview. Purge périodique
-- prévue mais PAS encore automatisée (pas de pg_cron ici) :
--   DELETE FROM dev_logs WHERE ts < now() - interval '30 days';
-- (à décider/planifier séparément.)

CREATE TABLE IF NOT EXISTS dev_logs (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ts         TIMESTAMPTZ NOT NULL DEFAULT now(),
  client_ts  TIMESTAMPTZ,
  session_id TEXT,
  channel    TEXT NOT NULL CHECK (channel IN ('chart', 'ux', 'net')),
  level      TEXT NOT NULL DEFAULT 'info' CHECK (level IN ('debug', 'info', 'warn', 'error')),
  event      TEXT NOT NULL,
  data       JSONB,
  url        TEXT,
  user_agent TEXT,
  app_env    TEXT CHECK (app_env IS NULL OR app_env IN ('preview', 'development'))
);

CREATE INDEX IF NOT EXISTS idx_dev_logs_ts ON dev_logs (ts DESC);
CREATE INDEX IF NOT EXISTS idx_dev_logs_channel_ts ON dev_logs (channel, ts DESC);
CREATE INDEX IF NOT EXISTS idx_dev_logs_session_id ON dev_logs (session_id);
CREATE INDEX IF NOT EXISTS idx_dev_logs_event ON dev_logs (event);

ALTER TABLE dev_logs ENABLE ROW LEVEL SECURITY;

-- Aucune policy pour anon/authenticated : RLS activée + 0 policy = tout
-- refusé sauf service_role (qui bypass RLS par définition Supabase).

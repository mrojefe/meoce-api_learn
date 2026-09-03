-- ============================================================
-- F26 + F27 — Tables pour workers (logs + RAW trade-securities)
-- ============================================================
-- Contexte :
-- Les workers Fly.io tournent encore sur OLD DB car ces 2 tables
-- manquent dans NEW. Sans elles, le switch des secrets Fly.io -> NEW
-- = crash au 1er run (log_run_started() echoue, upsert echoue).
--
-- F26 - scraper_runs : table de logs commune a tous les workers
--   (BOC, EOD, trade-securities, intraday). 1 row par run.
--
-- F27 - brvm_traded_securities : table RAW pour worker trade-sec
--   (scrape volume/value/trades quotidiens BRVM). Garde le data brut.
--   En meme temps, le worker fera UPDATE daily_candles inline (Option C
--   advisor) pour propager quantity/value/trade_count vers la table
--   metier. Pattern productionise depuis ingest_enrichment_data.py (D132).
--
-- RLS : deny-all sur les 2 (service_role uniquement, comme audit_logs)
-- ============================================================

-- ----------------------------------------------------------------
-- F26 : scraper_runs
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.scraper_runs (
  id              BIGSERIAL    PRIMARY KEY,
  worker_name     TEXT         NOT NULL,
  run_id          TEXT         NOT NULL,
  started_at      TIMESTAMPTZ  NOT NULL,
  completed_at    TIMESTAMPTZ,
  status          TEXT         NOT NULL
                               CHECK (status IN ('running','succeeded','failed')),
  items_processed INTEGER,
  errors_count    INTEGER,
  r2_snapshot_key TEXT,
  error_summary   TEXT
);

-- Index pour requetes "dernier run par worker"
CREATE INDEX idx_scraper_runs_worker
  ON public.scraper_runs(worker_name, started_at DESC);

-- Index partiel pour alertes "runs failed recents"
CREATE INDEX idx_scraper_runs_failed
  ON public.scraper_runs(worker_name, started_at DESC)
  WHERE status = 'failed';

-- RLS : deny-all (logs internes, service_role uniquement)
ALTER TABLE public.scraper_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY no_public_access ON public.scraper_runs
  FOR ALL USING (false) WITH CHECK (false);


-- ----------------------------------------------------------------
-- F27 : brvm_traded_securities (table RAW, legacy schema)
-- ----------------------------------------------------------------
-- Identique a OLD.brvm_traded_securities pour compat directe.
-- 1 row = 1 (date, code) avec les valeurs scrapees BRVM bfin.brvm.org.
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.brvm_traded_securities (
  id                      BIGSERIAL    PRIMARY KEY,
  date                    DATE         NOT NULL,
  code                    TEXT         NOT NULL,
  description             TEXT,
  previous_closing_price  NUMERIC,
  current_closing_price   NUMERIC,
  traded_volume           BIGINT,
  number_of_trades        INTEGER,
  traded_value            NUMERIC,
  created_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (date, code)
);

-- Index pour requetes "historique par code"
CREATE INDEX idx_brvm_ts_code
  ON public.brvm_traded_securities(code);

-- RLS : deny-all (table RAW datalake, service_role uniquement)
ALTER TABLE public.brvm_traded_securities ENABLE ROW LEVEL SECURITY;
CREATE POLICY no_public_access ON public.brvm_traded_securities
  FOR ALL USING (false) WITH CHECK (false);

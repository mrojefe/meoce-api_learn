CREATE TABLE IF NOT EXISTS scraper_run_log (
    id          BIGSERIAL PRIMARY KEY,
    dag_run_id  TEXT,
    section     TEXT        NOT NULL,
    docs_found  INTEGER     NOT NULL DEFAULT 0,
    docs_new    INTEGER     NOT NULL DEFAULT 0,
    status      TEXT        NOT NULL DEFAULT 'ok',
    message     TEXT,
    ran_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_srl_ran_at  ON scraper_run_log(ran_at DESC);
CREATE INDEX IF NOT EXISTS ix_srl_status  ON scraper_run_log(status);
CREATE INDEX IF NOT EXISTS ix_srl_section ON scraper_run_log(section);

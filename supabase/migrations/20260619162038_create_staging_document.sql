CREATE TABLE IF NOT EXISTS staging_document (
    id          BIGSERIAL PRIMARY KEY,
    source      TEXT        NOT NULL DEFAULT 'brvm',
    url         TEXT        NOT NULL,
    filename    TEXT        NOT NULL,
    section     TEXT,
    dl_state    TEXT        NOT NULL DEFAULT 'pending',
    r2_key      TEXT,
    file_hash   TEXT,
    attempts    INTEGER     NOT NULL DEFAULT 0,
    last_error  TEXT,
    first_seen  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT staging_document_url_unique UNIQUE (url)
);

CREATE INDEX IF NOT EXISTS ix_sd_dl_state  ON staging_document(dl_state);
CREATE INDEX IF NOT EXISTS ix_sd_source    ON staging_document(source);
CREATE INDEX IF NOT EXISTS ix_sd_section   ON staging_document(section);
CREATE INDEX IF NOT EXISTS ix_sd_filename  ON staging_document(filename);
CREATE INDEX IF NOT EXISTS ix_sd_source_state ON staging_document(source, dl_state);

CREATE OR REPLACE FUNCTION update_staging_document_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_staging_document_updated_at ON staging_document;
CREATE TRIGGER trg_staging_document_updated_at
    BEFORE UPDATE ON staging_document
    FOR EACH ROW EXECUTE FUNCTION update_staging_document_updated_at();

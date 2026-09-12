-- Create a non-superuser Postgres role for the app's own direct queries.
-- APPLIED 2026-09-13 against meoce_prod. Per ADR-0001 / ADR-0010's flagged
-- future work: the app previously connected as `postgres` (superuser,
-- BYPASSRLS), which made every RLS policy already written in this rebuild
-- a complete no-op.
--
-- Targets the "meoce_prod" database on the dbmeoce instance (uuid
-- cgc4b11uvjeii306nn36iny9) -- NOT that instance's default "postgres"
-- database. GRANT ON ALL TABLES IN SCHEMA and ALTER DEFAULT PRIVILEGES are
-- per-database, so this must run while connected to meoce_prod specifically,
-- or api_user ends up with rights on the wrong, empty database.
--
-- <CHANGE_ME> below: replace with a real, generated password before running
-- again anywhere else. Never reuse the superuser password, and never commit
-- the real value -- it belongs only in .env (gitignored).

CREATE ROLE api_user
    LOGIN
    PASSWORD '<CHANGE_ME>'
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOBYPASSRLS
    NOREPLICATION;

GRANT CONNECT ON DATABASE meoce_prod TO api_user;
GRANT USAGE ON SCHEMA public TO api_user;

-- Existing tables/sequences at the time this is run.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO api_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO api_user;

-- Any table/sequence created AFTER this point (future migrations) also
-- gets these same rights automatically -- without this, every new
-- migration would need its own manual GRANT.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO api_user;

-- Note on RLS: switching the app's connection from `postgres` to
-- `api_user` removes the automatic superuser bypass, which is
-- necessary but not sufficient for the RLS policies already written in
-- this rebuild to actually work. Those policies check `auth.uid()`,
-- which is a Supabase-Auth convention this app's own hand-rolled JWT
-- system never populates (see ADR-0010). Real per-account protection in
-- this app still comes from explicit ownership checks in application
-- code (already implemented, see M10 step 8 in the course), not from
-- RLS -- this role change alone does not turn RLS "on" in any
-- meaningful sense.

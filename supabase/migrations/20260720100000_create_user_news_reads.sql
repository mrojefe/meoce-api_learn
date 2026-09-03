-- Suivi "article lu/non lu" par utilisateur — panneau news de la page
-- graphique (refonte 2026-07-20). Même pattern que user_instrument_flags
-- (PK composite, ON DELETE CASCADE) — voir 20260517130240_initial_schema.sql.

CREATE TABLE IF NOT EXISTS user_news_reads (
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  article_id UUID        NOT NULL REFERENCES news_articles(id) ON DELETE CASCADE,
  read_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, article_id)
);

CREATE INDEX IF NOT EXISTS idx_user_news_reads_article ON user_news_reads(article_id);

ALTER TABLE user_news_reads ENABLE ROW LEVEL SECURITY;

-- Dormante (auth maison, pas Supabase Auth -> auth.uid() = NULL) mais posée
-- par cohérence avec le reste du schéma (défense en profondeur si l'auth
-- change un jour) — l'isolation réelle est le filtre user_id côté API
-- (service_role bypass RLS), voir user_alerts pour le même motif.
CREATE POLICY own_all ON user_news_reads
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

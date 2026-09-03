-- Commentaires publics sur les articles de news. Commentaires PLATS (pas de
-- réponses/threads) — pattern volontairement simple, calqué sur news_reports
-- (20260723080000) pour la forme, et sur user_alerts/user_drawings pour le
-- soft-delete (deleted_at, jamais de vrai DELETE SQL).
CREATE TABLE IF NOT EXISTS news_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  article_id UUID NOT NULL REFERENCES news_articles(id) ON DELETE CASCADE,
  content TEXT NOT NULL CHECK (char_length(content) BETWEEN 1 AND 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS news_comments_article_id_idx
  ON news_comments(article_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS news_comments_user_id_idx
  ON news_comments(user_id);

ALTER TABLE news_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY news_comments_own_all ON news_comments
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

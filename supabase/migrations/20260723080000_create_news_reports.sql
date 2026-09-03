-- Signalement d'article par un utilisateur (bouton "Signaler un problème",
-- référence TradingView) — plusieurs signalements possibles par (user, article)
-- contrairement aux signets (couleur unique) : PK id classique, pas composite.
CREATE TABLE IF NOT EXISTS news_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  article_id UUID NOT NULL REFERENCES news_articles(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN ('incorrect_info', 'biased_reporting', 'scam_fraud', 'hidden_ads', 'technical_issue', 'other')),
  comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_news_reports_article_id ON news_reports(article_id);
CREATE INDEX IF NOT EXISTS idx_news_reports_user_id ON news_reports(user_id);

ALTER TABLE news_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_all ON news_reports
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

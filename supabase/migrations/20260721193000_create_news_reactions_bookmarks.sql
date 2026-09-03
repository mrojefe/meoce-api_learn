-- Like/dislike + signets colorés sur les articles news (demande explicite
-- user 2026-07-21) — même pattern que user_news_reads (PK composite,
-- ON DELETE CASCADE, RLS dormante posée par cohérence, isolation réelle via
-- service_role + filtre user_id côté API).

-- Compteurs dénormalisés sur news_articles : évite un COUNT(*) par page à
-- chaque affichage de la liste — mis à jour côté service (read-modify-write,
-- volume trop faible pour justifier une fonction Postgres atomique).
ALTER TABLE news_articles
  ADD COLUMN IF NOT EXISTS likes_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dislikes_count INTEGER NOT NULL DEFAULT 0;

-- Une réaction par (user, article) — cliquer à nouveau la même réaction la
-- retire (toggle), cliquer l'autre la remplace. Logique côté service.
CREATE TABLE IF NOT EXISTS user_news_reactions (
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  article_id UUID        NOT NULL REFERENCES news_articles(id) ON DELETE CASCADE,
  reaction   TEXT        NOT NULL CHECK (reaction IN ('like', 'dislike')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, article_id)
);

CREATE INDEX IF NOT EXISTS idx_user_news_reactions_article ON user_news_reactions(article_id);

ALTER TABLE user_news_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_all ON user_news_reactions
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Signets colorés — la palette de couleurs valides N'EST PAS figée ici : FK
-- vers `flag_colors` (migration 20260721140000, déjà la source unique des
-- couleurs de fanion watchlist) au lieu d'un CHECK en dur — règle JF « les
-- couleurs possibles doivent être en BD, pas de hardcode ». Le frontend
-- n'affiche que 3 boutons (bleu/vert/rouge) par choix produit, mais la
-- contrainte elle-même reste ouverte à toute la palette existante.
-- Une seule couleur active par article pour un utilisateur donné (re-upsert
-- pour changer, delete pour retirer). Index (user_id, color) : c'est la
-- requête du filtre "voir mes signets rouges" par exemple.
CREATE TABLE IF NOT EXISTS user_news_bookmarks (
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  article_id UUID        NOT NULL REFERENCES news_articles(id) ON DELETE CASCADE,
  color      TEXT        NOT NULL REFERENCES flag_colors(id) ON UPDATE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, article_id)
);

CREATE INDEX IF NOT EXISTS idx_user_news_bookmarks_user_color ON user_news_bookmarks(user_id, color);

ALTER TABLE user_news_bookmarks ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_all ON user_news_bookmarks
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Modification de commentaire : ajoute updated_at (rempli uniquement à
-- l'édition, jamais à la création — permet d'afficher "modifié" côté
-- frontend sans ambiguïté avec created_at).
ALTER TABLE news_comments ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

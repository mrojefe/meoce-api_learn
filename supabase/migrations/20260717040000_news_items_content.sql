-- Ajoute le texte intégral de l'article (récupéré depuis sa propre page,
-- pas seulement le chapeau tronqué de la page de liste) — permet de lire
-- l'article directement sur le site sans repartir vers la source externe.
-- NULL tant que non (encore) récupéré (ex. Richbourse : bloqué par captcha,
-- reste au lien externe uniquement).

ALTER TABLE public.news_items ADD COLUMN IF NOT EXISTS content TEXT;

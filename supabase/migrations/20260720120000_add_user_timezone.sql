-- Fuseau horaire utilisateur, appliqué à l'affichage sur toute la
-- plateforme (news, live, watchlist, graphique) — NULL = pas encore
-- détecté/choisi, le frontend applique alors le fuseau du navigateur en
-- repli le temps de la 1ère détection auto (puis persisté ici).
ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS timezone TEXT;

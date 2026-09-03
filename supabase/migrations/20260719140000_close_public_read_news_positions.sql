-- Audit sécurité 2026-07-19 : PostgREST est joignable publiquement avec la
-- clé anon (livrée au navigateur, publique par nature). Les policies
-- ci-dessous étaient `USING(true)` / basées uniquement sur is_public,
-- donc lisibles en clair via /rest/v1/... en contournant TOUTE la logique
-- applicative (bornage de date, masquage des source_id, masquage des
-- montants absolus des portefeuilles publics).
--
-- L'API (service_role, bypass RLS) est déjà le seul chemin de lecture
-- utilisé en pratique pour ces tables (news.py -> get_admin_db(),
-- portfolios.py -> get_admin_db() partout) : retirer ces policies ne casse
-- rien côté API, ça ferme uniquement l'accès direct PostgREST public.

DROP POLICY IF EXISTS read_all ON news_articles;
DROP POLICY IF EXISTS read_all ON news_article_instruments;
DROP POLICY IF EXISTS public_read ON positions;

-- Durcissement RLS + search_path (findings audit SEV-022 / SEV-023 / SEV-029).
-- Idempotent (peut être rejoué sans erreur). service_role BYPASSE la RLS → le trafic
-- applicatif actuel (via service_role) n'est pas affecté ; c'est de la défense en profondeur
-- (protège si le rôle authenticated est un jour utilisé — cf. chantier RLS H2).

-- ── SEV-022 : watchlist_sections sans RLS (régression) ────────────────────────
-- Même patron que watchlist_items : accès borné au propriétaire de la watchlist parente,
-- lecture publique si la watchlist est publique.
ALTER TABLE public.watchlist_sections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS own_all ON public.watchlist_sections;
CREATE POLICY own_all ON public.watchlist_sections FOR ALL
  USING (EXISTS (SELECT 1 FROM public.watchlists w
                 WHERE w.id = watchlist_sections.watchlist_id AND w.user_id = auth.uid()));

DROP POLICY IF EXISTS public_read ON public.watchlist_sections;
CREATE POLICY public_read ON public.watchlist_sections FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.watchlists w
                 WHERE w.id = watchlist_sections.watchlist_id AND w.is_public = true));

-- ── SEV-023 : tables internes de scraping sans RLS → deny-all ─────────────────
-- staging_document / scraper_run_log ne concernent QUE les workers (service_role, qui
-- bypasse la RLS). On active la RLS SANS policy → tout accès anon/authenticated est refusé.
ALTER TABLE public.staging_document ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scraper_run_log  ENABLE ROW LEVEL SECURITY;
-- Ceinture + bretelles : retirer aussi les GRANTs directs éventuels.
REVOKE ALL ON public.staging_document FROM anon, authenticated;
REVOKE ALL ON public.scraper_run_log  FROM anon, authenticated;

-- ── SEV-029 : RPC SECURITY DEFINER sans search_path figé, grantée à anon ──────
-- On PIN le search_path (anti-injection via un schéma antérieur). On évite '' qui casserait
-- la fonction si son corps n'est pas entièrement qualifié : pg_catalog, public suffit à
-- neutraliser l'injection tout en gardant la résolution des tables publiques.
ALTER FUNCTION public.get_market_snapshot_v2() SET search_path = pg_catalog, public;

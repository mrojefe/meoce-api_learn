-- ⚠️ MIGRATION RECONSTITUÉE (2026-07-25) — le fichier d'origine n'a JAMAIS été
-- commité : la migration avait été appliquée directement en production et
-- `schema_migrations` la référençait sans qu'aucun fichier n'existe. L'audit du
-- 2026-07-25 a relevé 15 versions dans ce cas — une reconstruction de la base
-- depuis les migrations aurait produit un schéma DIFFÉRENT de la production.
--
-- Contenu déduit du schéma RÉEL en production, pas du texte d'origine. Écrit de
-- façon IDEMPOTENTE : sans effet sur la prod (version déjà enregistrée), correct
-- sur une base reconstruite de zéro.

-- watchlist_sections était la SEULE table utilisateur sans RLS (relevé audit).
ALTER TABLE public.watchlist_sections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS own_all ON public.watchlist_sections;
CREATE POLICY own_all ON public.watchlist_sections FOR ALL
  USING (EXISTS (SELECT 1 FROM public.watchlists w
                 WHERE w.id = watchlist_sections.watchlist_id AND w.user_id = auth.uid()));

DROP POLICY IF EXISTS public_read ON public.watchlist_sections;
CREATE POLICY public_read ON public.watchlist_sections FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.watchlists w
                 WHERE w.id = watchlist_sections.watchlist_id AND w.is_public = true));

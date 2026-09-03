-- ⚠️ MIGRATION RECONSTITUÉE (2026-07-25) — le fichier d'origine n'a JAMAIS été
-- commité : la migration avait été appliquée directement en production et
-- `schema_migrations` la référençait sans qu'aucun fichier n'existe. L'audit du
-- 2026-07-25 a relevé 15 versions dans ce cas — une reconstruction de la base
-- depuis les migrations aurait produit un schéma DIFFÉRENT de la production.
--
-- Contenu déduit du schéma RÉEL en production, pas du texte d'origine. Écrit de
-- façon IDEMPOTENTE : sans effet sur la prod (version déjà enregistrée), correct
-- sur une base reconstruite de zéro.

-- Borne les lectures ANONYMES intraday aux 10 derniers jours : sans ça, le
-- corpus intraday complet était aspirable via PostgREST.
DO $do$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['intraday_snapshots','intraday_chart_points',
                           'intraday_transactions','intraday_meta_data','order_book_levels'] LOOP
    IF to_regclass('public.'||t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS read_all ON public.%I', t);
      EXECUTE format($f$CREATE POLICY read_all ON public.%I FOR SELECT
                        USING (market_date >= (CURRENT_DATE - INTERVAL '10 days'))$f$, t);
    END IF;
  END LOOP;
END $do$;

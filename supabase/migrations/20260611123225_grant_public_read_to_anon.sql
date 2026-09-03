-- ============================================================
-- GRANT SELECT aux rôles anon + authenticated sur les tables
-- à policy RLS read_all (données publiques BRVM).
--
-- Contexte (ARCHITECTURE_MEOCE_V1.md, décision D-B) :
-- l'API lisait tout avec la service_role (qui bypasse RLS et grants),
-- donc l'absence de GRANT table-level pour anon est passée inaperçue.
-- En passant l'API sur la clé anon, PostgREST renvoie
-- "42501 permission denied" malgré les policies read_all.
--
-- RLS reste activée : le GRANT donne l'accès au niveau table,
-- la policy read_all (USING true) autorise les lignes.
-- Les tables user (portfolios, watchlists, alertes…) ne sont PAS
-- concernées : leurs policies restent owner-only.
-- ============================================================

GRANT SELECT ON TABLE
  public.countries,
  public.currencies,
  public.currency_rate_presets,
  public.exchanges,
  public.sectors,
  public.subsectors,
  public.instrument_types,
  public.instruments,
  public.daily_candles,
  public.daily_volume,
  public.dividends,
  public.corporate_actions,
  public.economic_indicators,
  public.intraday_snapshots,
  public.intraday_chart_points,
  public.intraday_transactions,
  public.intraday_meta_data,
  public.order_book_levels,
  public.news_sources,
  public.news_articles,
  public.news_article_instruments,
  public.bond_candles,
  public.bond_details,
  public.right_candles,
  public.right_details,
  public.boc_documents,
  public.boc_instrument_mentions
TO anon, authenticated;

-- La migration 20260611120000 a recréé la vue daily_candles_with_volume
-- en ne la grantant qu'à anon + authenticated : la service_role (workers,
-- ancienne API) a perdu l'accès → "permission denied for view". On le rend.
GRANT SELECT ON public.daily_candles_with_volume TO service_role;

-- Vérification : liste les tables read_all où anon n'a toujours pas SELECT
SELECT t.tablename
FROM pg_tables t
WHERE t.schemaname = 'public'
  AND EXISTS (
    SELECT 1 FROM pg_policies p
    WHERE p.schemaname = 'public'
      AND p.tablename = t.tablename
      AND p.policyname = 'read_all'
  )
  AND NOT has_table_privilege('anon', format('public.%I', t.tablename), 'SELECT');

-- ============================================================
-- Migration : Correction advisors sécurité Supabase
-- Date      : 2026-06-11
--
-- Problèmes corrigés :
--   1. exec_sql SECURITY DEFINER accessible par anon/authenticated
--      → REVOKE EXECUTE + SET search_path = ''
--   2. daily_candles : policy read_all existe mais RLS désactivé
--      → ENABLE ROW LEVEL SECURITY
--   3. instruments : idem daily_candles
--      → ENABLE ROW LEVEL SECURITY
--   4. daily_volume : RLS activé mais aucune policy
--      → CREATE POLICY read_all
--   5. daily_candles_with_volume : vue SECURITY DEFINER
--      → Recréer en SECURITY INVOKER
-- ============================================================

-- ============================================================
-- 1. exec_sql — retirer l'accès public + sécuriser search_path
--    Cette fonction ne doit être appelable que par service_role
--    (backend API), jamais via l'API REST publique.
-- ============================================================
CREATE OR REPLACE FUNCTION public.exec_sql(query text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  result jsonb;
BEGIN
  EXECUTE 'SELECT pg_catalog.jsonb_agg(t) FROM (' || query || ') t' INTO result;
  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.exec_sql(text) FROM anon, authenticated;

-- ============================================================
-- 2. daily_candles — activer RLS (policy read_all déjà en place)
-- ============================================================
ALTER TABLE public.daily_candles ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 3. instruments — activer RLS (policy read_all déjà en place)
-- ============================================================
ALTER TABLE public.instruments ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. daily_volume — ajouter policy read_all
--    Données publiques, lecture libre pour tous.
-- ============================================================
CREATE POLICY read_all ON public.daily_volume
  FOR SELECT
  USING (true);

-- ============================================================
-- 5. daily_candles_with_volume — recréer en SECURITY INVOKER
--    La vue hérite maintenant des permissions de l'appelant
--    (respecte le RLS de daily_candles et daily_volume).
-- ============================================================
DROP VIEW IF EXISTS public.daily_candles_with_volume;

CREATE VIEW public.daily_candles_with_volume
WITH (security_invoker = true)
AS
SELECT
  c.instrument_id,
  c.date,
  c.open_price,
  c.high_price,
  c.low_price,
  c.close_price,
  c.previous_close,
  c.change_percent,
  c.created_at,
  c.updated_at,
  COALESCE(v.quantity, 0::bigint)   AS volume,
  COALESCE(v.value,    0::numeric)  AS value_traded,
  COALESCE(v.trade_count, 0)        AS trade_count
FROM public.daily_candles c
LEFT JOIN public.daily_volume v
  ON c.instrument_id = v.instrument_id
 AND c.date = v.date;

-- Accès en lecture pour tous (données publiques BRVM)
GRANT SELECT ON public.daily_candles_with_volume TO anon, authenticated;

-- ============================================================
-- VÉRIFICATION — affiche l'état RLS et les grants post-migration
-- ============================================================
SELECT
  t.tablename,
  t.rowsecurity AS rls_enabled,
  COUNT(p.policyname) AS nb_policies
FROM pg_tables t
LEFT JOIN pg_policies p ON p.tablename = t.tablename AND p.schemaname = t.schemaname
WHERE t.schemaname = 'public'
  AND t.tablename IN ('daily_candles', 'instruments', 'daily_volume')
GROUP BY t.tablename, t.rowsecurity
ORDER BY t.tablename;

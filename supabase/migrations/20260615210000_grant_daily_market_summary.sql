-- Migration: grant read access to daily_market_summary
-- Raison: table inaccessible via service_role/anon/authenticated → résumés BOC
--         invisibles côté frontend et API

GRANT SELECT ON public.daily_market_summary TO anon;
GRANT SELECT ON public.daily_market_summary TO authenticated;
GRANT SELECT ON public.daily_market_summary TO service_role;

-- Vérification que la table existe bien avant de sortir
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'daily_market_summary'
  ) THEN
    RAISE EXCEPTION 'Table daily_market_summary introuvable';
  END IF;
END $$;

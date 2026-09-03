-- Grants manquants sur tables récentes (culture_items sans GRANT -> permission denied)
GRANT SELECT ON public.culture_items TO anon;
GRANT SELECT ON public.culture_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.culture_items TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.daily_market_summary TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_preferences TO service_role;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'culture_items'
  ) THEN
    RAISE EXCEPTION 'Table culture_items introuvable';
  END IF;
END $$;

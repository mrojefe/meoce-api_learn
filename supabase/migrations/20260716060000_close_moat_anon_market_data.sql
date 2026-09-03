-- Ferme le MOAT : coupe l'accès DIRECT anon/authenticated aux données marché
-- propriétaires (prix / historique / événements scrapés). Ces tables ne doivent
-- être servies QUE via l'API (service_role → gating par palier + rate-limit).
--
-- Problème : elles portaient une policy `read_all` (USING true, rôle public) + un
-- grant SELECT anon → n'importe qui pouvait les aspirer en direct via PostgREST,
-- en contournant tout le gating de l'API (ex. bond_candles 282k lignes,
-- opcvm_nav_history 76k, documents 4238 = index des BOC + clés R2).
--
-- Sûr (audit code fait) : AUCUNE lecture via le client anon — opcvm.py et
-- bridge_portfolio.py lisent en service_role, les autres tables ne sont lues nulle
-- part dans l'API/frontend. service_role (BYPASSRLS) et les workers pipeline
-- (qui écrivent en service_role) ne sont PAS affectés.
--
-- Idempotent. Ne touche PAS les tables publiques légitimes (instruments, sectors,
-- currencies, exchanges, countries, instrument_types, platform_config, features,
-- subscription_plans, daily_market_summary, news_*, tableau de vote).

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'bond_candles','bond_details','right_candles','right_details',
    'opcvm_nav_history','opcvm_funds','documents','dividends','corporate_actions',
    'boc_embeddings','boc_instrument_mentions','economic_indicators','bridge_recommendations'
  ]
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS read_all ON public.%I', t);
    EXECUTE format('REVOKE SELECT ON public.%I FROM anon, authenticated', t);
  END LOOP;
END $$;

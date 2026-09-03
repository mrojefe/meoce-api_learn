-- Durcissement (réserve de la revue Fable sur la fermeture du moat) : les 13 tables
-- marché gardaient des grants larges anon/authenticated (INSERT/UPDATE/DELETE/TRUNCATE/
-- REFERENCES/TRIGGER) hérités du grant PostgREST. INERTES (RLS ON + 0 policy bloque
-- déjà toute écriture) mais sales → REVOKE ALL nettoie complètement.
--
-- Sûr : aucun code n'écrit ces tables via le client anon/authenticated (workers &
-- API écrivent en service_role, BYPASSRLS, non affecté). Idempotent (REVOKE no-op si
-- déjà retiré). Complète 20260716060000 (qui avait retiré le SELECT + la policy).

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'bond_candles','bond_details','right_candles','right_details',
    'opcvm_nav_history','opcvm_funds','documents','dividends','corporate_actions',
    'boc_embeddings','boc_instrument_mentions','economic_indicators','bridge_recommendations'
  ]
  LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
  END LOOP;
END $$;

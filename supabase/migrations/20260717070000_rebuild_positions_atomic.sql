-- Rebuild ATOMIQUE des positions d'un portefeuille.
--
-- Avant : app/services/portfolios.py faisait DELETE puis INSERT en DEUX appels séparés
-- (non transactionnels). Un crash / erreur réseau ENTRE les deux laissait le portefeuille
-- SANS AUCUNE position (perte de données réelle) — exactement le pattern delete+insert
-- non atomique proscrit. Une fonction plpgsql s'exécute dans UNE transaction implicite :
-- delete + insert réussissent ou échouent ENSEMBLE.
--
-- Colonnes explicites = strictement celles que fournissait l'INSERT Python
-- (portfolio_id, instrument_id, quantity, avg_cost, realized_pnl, status, opened_at) ;
-- direction ('long') et updated_at (now()) gardent leur DEFAULT, comportement inchangé.
-- COALESCE(opened_at, now()) : petite robustesse (une position sans opened_at prend now()
-- au lieu de faire échouer tout le rebuild — la colonne est NOT NULL DEFAULT now()).
--
-- Sécurité : EXECUTE réservé à service_role (l'API appelle en get_admin_db et a déjà
-- validé la propriété du portefeuille avant l'appel) ; anon/authenticated révoqués.
-- Idempotent (CREATE OR REPLACE + REVOKE/GRANT). search_path figé (durcissement RPC).

CREATE OR REPLACE FUNCTION public.rebuild_positions(p_portfolio_id uuid, p_rows jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.positions WHERE portfolio_id = p_portfolio_id;

  IF p_rows IS NOT NULL AND jsonb_typeof(p_rows) = 'array' AND jsonb_array_length(p_rows) > 0 THEN
    INSERT INTO public.positions
      (portfolio_id, instrument_id, quantity, avg_cost, realized_pnl, status, opened_at)
    SELECT
      p_portfolio_id,
      (x->>'instrument_id')::uuid,
      (x->>'quantity')::numeric,
      (x->>'avg_cost')::numeric,
      (x->>'realized_pnl')::numeric,
      x->>'status',
      COALESCE((x->>'opened_at')::timestamptz, now())
    FROM jsonb_array_elements(p_rows) AS x;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.rebuild_positions(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rebuild_positions(uuid, jsonb) TO service_role;

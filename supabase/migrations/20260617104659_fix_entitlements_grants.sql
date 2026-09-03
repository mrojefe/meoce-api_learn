-- La résolution doit fonctionner quel que soit le rôle appelant (service_role côté API).
-- SECURITY DEFINER : s'exécute avec les droits du propriétaire (accès tables garanti).
ALTER FUNCTION get_user_entitlements(UUID) SECURITY DEFINER;
ALTER FUNCTION get_user_entitlements(UUID) SET search_path = public;

GRANT EXECUTE ON FUNCTION get_user_entitlements(UUID) TO anon, authenticated, service_role;
GRANT SELECT ON public.features TO anon, authenticated, service_role;
GRANT SELECT ON public.user_features TO authenticated, service_role;

-- ============================================================================
-- get_user_entitlements(p_user, p_is_anon) — distingue enfin VISITEUR vs GRATUIT
--
-- Bug racine (audit 2026-07-22, "pastilles de plan incohérentes") : la fonction
-- ne connaissait QUE `free_default`. Un visiteur non connecté était résolu via
-- l'UUID nul (NIL_UUID) et recevait donc la carte FREE — alors que la colonne
-- `features.anon_default` (migration 20260721150000) existe déjà pour ce cas
-- précis, mais n'était consommée que par /api/platform/config, jamais par ce
-- RPC (le seul appelé par entitlementsStore/useLazyHistory côté "vrais" droits).
--
-- Signature étendue avec un paramètre par défaut (`p_is_anon boolean DEFAULT false`)
-- : tous les appelants existants (frontend Next.js, meoce-api) continuent de
-- fonctionner sans modification tant qu'ils ne passent pas ce flag — seuls les
-- 2 points d'entrée corrigés dans la foulée (route entitlements Next.js,
-- resolve_entitlements côté meoce-api) l'activent pour un visiteur.
-- ============================================================================

CREATE OR REPLACE FUNCTION get_user_entitlements(p_user UUID, p_is_anon BOOLEAN DEFAULT false)
RETURNS JSONB
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    jsonb_object_agg(
      f.key,
      CASE WHEN p_is_anon THEN f.anon_default ELSE COALESCE(eff.value, f.free_default) END
    ),
    '{}'::jsonb
  )
  FROM features f
  LEFT JOIN LATERAL (
    SELECT uf.value
    FROM user_features uf
    WHERE uf.user_id = p_user
      AND uf.feature_key = f.key
      AND (uf.expires_at IS NULL OR uf.expires_at > now())
    ORDER BY uf.granted_at DESC
    LIMIT 1
  ) eff ON true
  WHERE f.is_active;
$$;

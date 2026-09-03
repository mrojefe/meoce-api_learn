-- ============================================================================
-- get_user_entitlements — intègre enfin l'ABONNEMENT ACTIF (subscription_plans)
--
-- Bug critique (signalé 2026-07-22, "mon compte pro est connecté et on lui dit
-- aussi limite") : le docstring de app/services/entitlements.py affirmait que
-- la priorité de résolution était :
--   valeur user_features accordée > features du PLAN de l'abonnement actif > free_default
-- ... mais la fonction SQL n'a JAMAIS lu ni `subscriptions` ni `subscription_plans` :
-- seul `user_features` (octrois individuels à-la-carte) était consulté. Un
-- abonné PAYANT actif (table `subscriptions`, status='active') sans octroi
-- individuel explicite dans `user_features` recevait donc exactement les
-- mêmes droits qu'un visiteur/gratuit — vérifié en direct sur un compte
-- premium réel (`subscriptions.status='active'`, `user_features` vide).
--
-- Cette migration ajoute la lecture du plan actif comme 2e priorité, entre
-- l'octroi individuel et le défaut gratuit/visiteur — conforme à ce que le
-- code affirmait déjà faire.
-- ============================================================================

CREATE OR REPLACE FUNCTION get_user_entitlements(p_user UUID, p_is_anon BOOLEAN DEFAULT false)
RETURNS JSONB
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    jsonb_object_agg(
      f.key,
      CASE
        WHEN p_is_anon THEN f.anon_default
        ELSE COALESCE(uf_eff.value, plan_eff.value, f.free_default)
      END
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
  ) uf_eff ON true
  LEFT JOIN LATERAL (
    SELECT sp.features -> f.key AS value
    FROM subscriptions s
    JOIN subscription_plans sp ON sp.code = s.plan_code
    WHERE s.user_id = p_user
      AND s.status = 'active'
      AND sp.features ? f.key
    ORDER BY s.current_period_start DESC
    LIMIT 1
  ) plan_eff ON true
  WHERE f.is_active;
$$;

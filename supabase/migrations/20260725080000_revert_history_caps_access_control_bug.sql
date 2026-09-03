-- ============================================================================
-- CORRECTIF URGENT — la migration 20260725070000 a introduit une régression
-- d'accès réelle, pas juste un problème d'affichage.
--
-- `live_history_days` et `history_years_max` ne sont pas de simples valeurs
-- d'affichage : src/lib/data-tier.ts (resolveTierAccess) les lit pour décider
-- CÔTÉ SERVEUR si un compte a un accès illimité à l'historique intraday/daily.
-- `null` y signifie explicitement « pro, illimité » (voir commentaire ligne
-- 145-148 de ce fichier). En posant 89 / 27 à la place de null pour appliquer
-- la règle « jamais illimité à l'écran », j'ai plafonné de vrais comptes Pro à
-- 89 jours d'historique intraday — cause exacte du bug rapporté en prod :
-- un abonné Pro voyait « Limite d'historique de votre offre atteinte ».
--
-- Correctif : on restaure null (accès réel illimité, comportement d'origine)
-- pour plus ET pro. La règle « jamais illimité à l'écran » reste respectée
-- autrement : PlansSection.tsx masque déjà la ligne quand la valeur est null,
-- au lieu d'écrire le mot « Illimité » ou d'inventer un chiffre. Le plafond
-- chiffré réel (27 ans / 89 jours) n'a de sens que comme INFORMATION, jamais
-- comme valeur qui restreint l'accès — cette distinction n'était pas faite.
-- ============================================================================

UPDATE subscription_plans
   SET features = features
       || jsonb_build_object('history_years_max', NULL)
       || jsonb_build_object('history_years_default', NULL)
       || jsonb_build_object('live_history_days', NULL)
 WHERE code IN ('plus', 'pro');

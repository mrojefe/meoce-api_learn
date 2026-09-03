-- ============================================================================
-- Quotas d'alertes ajustés + libellés d'affichage (décision JF 2026-07-25)
--
-- Nouvelles valeurs (le quota MENSUEL devient la valeur mise en avant sur les
-- cartes d'abonnement ; le quota SIMULTANÉ reste un plafond distinct) :
--
--            actives simultanées   créées par mois
--   free              2                  10        (inchangé)
--   plus             10                  30        (mensuel : 50 → 30)
--   pro              25                  60        (les deux étaient illimités)
--
-- Libellés (affichés tels quels par PlansSection, qui lit le catalogue —
-- aucune valeur ni libellé n'est codé en dur côté frontend) :
--   « Portefeuilles réels »     → « Portefeuilles »
--   « Alertes créées par mois » → « Alertes par mois »
--
-- Idempotente : de simples UPDATE ciblés, rejouables sans effet de bord.
-- ============================================================================

-- 1) Libellés
UPDATE features SET label = 'Portefeuilles'    WHERE key = 'max_real_portfolios';
UPDATE features SET label = 'Alertes par mois' WHERE key = 'max_alerts_month';

-- 2) Quotas — MEOCE Plus : 30 alertes/mois (simultanées inchangées à 10)
UPDATE subscription_plans
   SET features = features || jsonb_build_object('max_alerts_month', 30)
 WHERE code = 'plus';

-- 3) Quotas — MEOCE Pro : 60/mois et 25 simultanées (fin de l'illimité alertes)
UPDATE subscription_plans
   SET features = features
       || jsonb_build_object('max_alerts_month', 60)
       || jsonb_build_object('max_alerts_active', 25)
 WHERE code = 'pro';

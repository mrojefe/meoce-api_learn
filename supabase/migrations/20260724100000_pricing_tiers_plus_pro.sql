-- ============================================================================
-- PRICING V2 — 3 paliers : free / plus (8 500) / pro (13 500)
--
-- Contexte (lu sur la base MEOCE réelle, dbmeoce.beojefe.com, le 2026-07-24) :
--   • subscription_plans = { free, premium } uniquement (pas de 'custom').
--   • subscriptions = 160 lignes : 157 free active, 3 premium active.
--   • catalogue features : 16 clés actives, multi_layout déjà inactive
--     (le gating multi-graphes passe par max_chart_panes, numérique).
--
-- Cette migration est ADDITIVE et NON-CASSANTE :
--   • on AJOUTE les plans 'plus' et 'pro' + 3 nouvelles clés features ;
--   • on remappe les 3 abonnements 'premium' -> 'pro' (premium = tout illimité,
--     c'est exactement le haut de gamme) puis on masque le plan 'premium' ;
--   • on NE TOUCHE PAS aux anciennes clés d'alertes par canal
--     (max_alerts_email_active / max_alerts_whatsapp_active) : elles restent
--     ACTIVES et lues par le code actuel. Leur désactivation se fera à l'ÉTAPE 2
--     (refonte de la garde d'alertes vers un comptage PAR ALERTE), en même temps
--     que le code — sinon un `getLimit` sur une clé absente = plus de plafond.
--
-- Idempotente : ON CONFLICT DO NOTHING + gardes NOT (features ? key) + WHERE
--               ciblés. Rejouable sans effet de bord.
-- À valider par Fable, à appliquer sur STAGING d'abord. Rien n'est supprimé.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Nouvelles clés du catalogue `features`
--    • max_alerts_active  : nb d'alertes ACTIVES simultanées (tous canaux confondus,
--                           1 alerte = 1 unité, qu'elle notifie par email/whatsapp/les deux)
--    • max_alerts_month   : nb d'alertes CRÉÉES dans le mois calendaire
--    • insights_ai_premium: accès aux analyses IA premium (exclusivité Pro)
-- free_default / anon_default = le palier gratuit (2 simult / 10 mois ; IA = non).
-- ----------------------------------------------------------------------------
INSERT INTO features (key, label, description, kind, free_default, anon_default, category, display_order) VALUES
  ('max_alerts_active', 'Alertes actives simultanées',
   'Nombre d''alertes actives en même temps (1 alerte = 1 unité, tous canaux confondus ; null = illimité)',
   'limit', '2'::jsonb, '2'::jsonb, 'alerts', 90),
  ('max_alerts_month', 'Alertes créées par mois',
   'Nombre d''alertes créées dans le mois calendaire (null = illimité)',
   'limit', '10'::jsonb, '10'::jsonb, 'alerts', 95),
  ('insights_ai_premium', 'Insights IA premium',
   'Accès aux analyses/insights assistés par IA (exclusivité Pro)',
   'boolean', 'false'::jsonb, 'false'::jsonb, 'ui', 200),
  ('max_custom_timeframes', 'Intervalles personnalisés',
   'Nombre d''intervalles (timeframes) personnalisés actifs qu''un user peut avoir créés (en supprimer libère un slot ; 0 = interdit, null = illimité)',
   'limit', '0'::jsonb, '0'::jsonb, 'ui', 205)
ON CONFLICT (key) DO NOTHING;
-- Note : la clé booléenne `custom_timeframes` reste ACTIVE pour l'instant (lue par
-- TimeframeSelector). L'étape 2 basculera le gate vers `max_custom_timeframes`
-- (compteur d'UT actives) et désactivera alors le booléen.

-- ----------------------------------------------------------------------------
-- 2) Nouveau plan MEOCE PLUS (8 500 XOF / mois)
--    Logique : on enlève les plafonds de confort, MAIS :
--      • multi-layout limité au NIVEAU 2 (max_chart_panes = 2)
--      • 2 fanions max (max_flags = 2)
--      • portefeuille réel = 1
--      • alertes : 10 simultanées / 50 par mois
--      • pas d'Insights IA (réservé Pro)
--    Compat : on renseigne aussi les anciennes clés par canal (10/10) pour que
--    le code actuel se comporte correctement jusqu'à l'étape 2.
-- ----------------------------------------------------------------------------
INSERT INTO subscription_plans (code, name, monthly_price_xof, yearly_price_xof, features, is_active, display_order) VALUES
  ('plus', 'MEOCE Plus', 8500, NULL, '{
    "max_alerts_active": 10,
    "max_alerts_month": 50,
    "max_alerts_email_active": 10,
    "max_alerts_whatsapp_active": 10,
    "max_chart_panes": 2,
    "max_flags": 2,
    "max_watchlists": null,
    "max_virtual_portfolios": null,
    "max_real_portfolios": 1,
    "max_screener_saves": 10,
    "max_indicators_on_chart": null,
    "max_news_bookmarks": null,
    "history_years_max": null,
    "history_years_default": null,
    "live_history_days": null,
    "realtime_candle": true,
    "pro_chart_types": true,
    "custom_timeframes": true,
    "max_custom_timeframes": 5,
    "news_feed": true,
    "insights_ai_premium": false
  }'::jsonb, true, 1)
ON CONFLICT (code) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 3) Nouveau plan MEOCE PRO (13 500 XOF / mois)
--    Tout illimité + exclusivités : Insights IA. Portefeuille réel = 3.
-- ----------------------------------------------------------------------------
INSERT INTO subscription_plans (code, name, monthly_price_xof, yearly_price_xof, features, is_active, display_order) VALUES
  ('pro', 'MEOCE Pro', 13500, NULL, '{
    "max_alerts_active": null,
    "max_alerts_month": null,
    "max_alerts_email_active": null,
    "max_alerts_whatsapp_active": null,
    "max_chart_panes": null,
    "max_flags": null,
    "max_watchlists": null,
    "max_virtual_portfolios": null,
    "max_real_portfolios": 3,
    "max_screener_saves": null,
    "max_indicators_on_chart": null,
    "max_news_bookmarks": null,
    "history_years_max": null,
    "history_years_default": null,
    "live_history_days": null,
    "realtime_candle": true,
    "pro_chart_types": true,
    "custom_timeframes": true,
    "max_custom_timeframes": null,
    "news_feed": true,
    "insights_ai_premium": true
  }'::jsonb, true, 2)
ON CONFLICT (code) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 4) Compléter les plans EXISTANTS avec les 3 nouvelles clés
--    (sinon un user free/premium n'aurait pas ces clés dans son entitlement).
--    Gardes NOT (features ? key) = idempotent, n'écrase jamais une valeur posée.
-- ----------------------------------------------------------------------------
UPDATE subscription_plans
   SET features = features
       || jsonb_build_object('max_alerts_active', 2)
       || jsonb_build_object('max_alerts_month', 10)
       || jsonb_build_object('insights_ai_premium', false)
       || jsonb_build_object('max_custom_timeframes', 0)
 WHERE code = 'free'
   AND NOT (features ? 'max_alerts_active');

UPDATE subscription_plans
   SET features = features
       || jsonb_build_object('max_alerts_active', null)
       || jsonb_build_object('max_alerts_month', null)
       || jsonb_build_object('insights_ai_premium', true)
       || jsonb_build_object('max_custom_timeframes', null)
 WHERE code = 'premium'
   AND NOT (features ? 'max_alerts_active');

-- ----------------------------------------------------------------------------
-- 5) Migration des 3 abonnements 'premium' -> 'pro'
--    premium = tout illimité = équivalent Pro. Les 3 comptes gardent leurs droits.
--    Idempotent : après passage, plus aucune ligne 'premium' (WHERE ne matche plus).
-- ----------------------------------------------------------------------------
UPDATE subscriptions SET plan_code = 'pro' WHERE plan_code = 'premium';

-- ----------------------------------------------------------------------------
-- 6) Masquer l'ancien plan 'premium' (conservé en base pour ne rien casser, mais
--    plus proposé). is_active=false le sort du catalogue affiché.
-- ----------------------------------------------------------------------------
UPDATE subscription_plans SET is_active = false WHERE code = 'premium';

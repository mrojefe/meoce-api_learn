-- Renomme ui_customization → custom_timeframes (nom trop vague).
-- La feature ne gate qu'une chose : les intervalles de temps personnalisés.
BEGIN;

UPDATE features
SET key   = 'custom_timeframes',
    label = 'Intervalles personnalisés'
WHERE key = 'ui_customization';

UPDATE subscription_plans
SET features = (features - 'ui_customization')
               || jsonb_build_object('custom_timeframes', features->'ui_customization')
WHERE features ? 'ui_customization';

UPDATE user_features
SET feature_key = 'custom_timeframes'
WHERE feature_key = 'ui_customization';

COMMIT;

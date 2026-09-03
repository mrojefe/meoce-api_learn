-- Coordonnées de contact plateforme (email + WhatsApp) — jusqu'ici codées en
-- dur et DIVERGENTES à plusieurs endroits du frontend (ProUpsellModal.tsx,
-- AboutPage.tsx avaient un ancien numéro WhatsApp incorrect). Centralisées
-- ici comme le reste de la config plateforme (available_timeframes, etc.) —
-- déjà servi publiquement par GET /api/platform/config (frontend), aucun
-- changement backend nécessaire au-delà de ce seed.
--
-- ATTENTION : ce numéro sert UNIQUEMENT au contact/support commercial — ne
-- pas confondre avec le WhatsApp utilisé par le pipeline d'ALERTES MEOCE
-- (WAHA, service technique séparé, autre numéro).
INSERT INTO platform_config (key, value) VALUES
  ('contact_email', '"contact@meoce.beojefe.com"'),
  ('contact_whatsapp_intl', '"2250702611265"'),
  ('contact_whatsapp_display', '"+225 07 02 61 12 65"')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();

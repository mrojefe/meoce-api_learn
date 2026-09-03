-- Zoho Mail ne supporte qu'un seul domaine sur le plan actuel — le user a
-- consolidé sur l'apex beojefe.com plutôt que meoce.beojefe.com. Ceci ne
-- concerne QUE le contact humain affiché publiquement (site, footer) ; les
-- emails AUTOMATIQUES applicatifs (vérification compte, alertes) restent sur
-- contact@meoce.beojefe.com car authentifiés DKIM via Brevo pour ce
-- sous-domaine spécifiquement — bascule différée le temps de configurer
-- l'authentification Brevo pour le domaine apex.
UPDATE platform_config
SET value = '"contactmeoce@beojefe.com"', updated_at = now()
WHERE key = 'contact_email';

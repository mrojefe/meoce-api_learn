-- ============================================================================
-- Règle produit (JF) : ne JAMAIS afficher « illimité » — toujours un MAX chiffré.
--
-- max_chart_panes du plan Pro était NULL (∞). Or l'interface ne propose de
-- toute façon que 3 panneaux au maximum (layouts single/dual/triple). Poser 3
-- ne retire donc AUCUN droit réel : c'est le plafond effectif, désormais
-- affichable honnêtement (« maximum 3 panneaux ») au lieu d'« illimité ».
-- Les autres clés à NULL du plan Pro nécessitent une décision produit (quels
-- plafonds ?) et restent inchangées ici.
-- ============================================================================
UPDATE subscription_plans
   SET features = features || jsonb_build_object('max_chart_panes', 3)
 WHERE code = 'pro';

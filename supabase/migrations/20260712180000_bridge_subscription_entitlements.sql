-- ⚠️ MIGRATION RECONSTITUÉE (2026-07-25) — le fichier d'origine n'a JAMAIS été
-- commité : la migration avait été appliquée directement en production et
-- `schema_migrations` la référençait sans qu'aucun fichier n'existe. L'audit du
-- 2026-07-25 a relevé 15 versions dans ce cas — une reconstruction de la base
-- depuis les migrations aurait produit un schéma DIFFÉRENT de la production.
--
-- Contenu déduit du schéma RÉEL en production, pas du texte d'origine. Écrit de
-- façon IDEMPOTENTE : sans effet sur la prod (version déjà enregistrée), correct
-- sur une base reconstruite de zéro.

-- Relie les entitlements au plan d'abonnement actif : jusque-là,
-- get_user_entitlements() ignorait `subscription_plans` et TOUT compte payant
-- était servi comme gratuit. La définition à jour de la fonction vit dans
-- 20260722110000_entitlements_include_active_plan.sql (qui la remplace) ;
-- ce fichier ne fait que garantir la présence de la table de liaison.
CREATE TABLE IF NOT EXISTS public.user_features (
  user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  feature_key text NOT NULL REFERENCES public.features(key) ON UPDATE CASCADE,
  value       text,
  source      text,
  source_ref  text,
  granted_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz,
  PRIMARY KEY (user_id, feature_key)
);
ALTER TABLE public.user_features ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS own_read ON public.user_features;
CREATE POLICY own_read ON public.user_features FOR SELECT USING (auth.uid() = user_id);

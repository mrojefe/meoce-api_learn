-- ⚠️ MIGRATION RECONSTITUÉE (2026-07-25) — le fichier d'origine n'a JAMAIS été
-- commité : la migration avait été appliquée directement en production et
-- `schema_migrations` la référençait sans qu'aucun fichier n'existe. L'audit du
-- 2026-07-25 a relevé 15 versions dans ce cas — une reconstruction de la base
-- depuis les migrations aurait produit un schéma DIFFÉRENT de la production.
--
-- Contenu déduit du schéma RÉEL en production, pas du texte d'origine. Écrit de
-- façon IDEMPOTENTE : sans effet sur la prod (version déjà enregistrée), correct
-- sur une base reconstruite de zéro.

-- Suppression en cascade : effacer un `user_profiles` doit effacer le `users`
-- miroir (et, par les FK ON DELETE CASCADE, toutes ses données).
-- NB : la fonction s'appelle finalement `cascade_delete_user` (le nom
-- `sync_user_deletion` de la version n'a jamais existé en base).
CREATE OR REPLACE FUNCTION public.cascade_delete_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  DELETE FROM public.users WHERE id = OLD.id;
  RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS trg_cascade_delete_user ON public.user_profiles;
CREATE TRIGGER trg_cascade_delete_user
AFTER DELETE ON public.user_profiles
FOR EACH ROW EXECUTE FUNCTION public.cascade_delete_user();

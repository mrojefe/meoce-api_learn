-- Corrige un 404 en production sur GET /api/user/profile (profil « introuvable » alors
-- qu'il existe) → casse le chargement de l'onglet Compte ET la bannière de vérification email.
--
-- Cause racine (confirmée en base) : la route sélectionne `avatar_url` sur `user_profiles`,
-- mais la colonne N'EXISTE PAS (dérive schéma). PostgREST renvoie une erreur de colonne
-- inconnue → la route retombe dans sa branche `error → 404 User not found`, trompeuse (le
-- profil existe : le select échoue). Toutes les autres colonnes du select existent bien ;
-- seule `avatar_url` manquait.
--
-- Le design l'attend partout : `authStore.avatarUrl`, `google-auth` (avatar Google), onglet
-- Compte de la modale Paramètres. Fix = déclarer la colonne (additive, nullable). Aucune
-- donnée touchée, idempotent.

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS avatar_url text;

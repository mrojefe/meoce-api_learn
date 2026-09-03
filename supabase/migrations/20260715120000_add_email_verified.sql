-- 20260715120000_add_email_verified.sql
-- Ajoute user_profiles.email_verified : jusqu'ici l'inscription/connexion par
-- email ne vérifiait QUE le mot de passe, jamais la propriété de l'adresse
-- (aucune preuve). Cette colonne trace la confirmation par lien envoyé à
-- l'inscription (token Redis 24h, route /api/auth/verify-email).
--
-- Idempotente et non destructive : ADD COLUMN IF NOT EXISTS, défaut false.
-- Les comptes existants restent à false (non vérifiés) — cohérent, ils n'ont
-- jamais confirmé ; ils pourront le faire via « renvoyer l'email de vérification ».
-- Le miroir public.users n'a pas besoin de la colonne (l'auth vit dans user_profiles).

ALTER TABLE public.user_profiles
    ADD COLUMN IF NOT EXISTS email_verified boolean NOT NULL DEFAULT false;

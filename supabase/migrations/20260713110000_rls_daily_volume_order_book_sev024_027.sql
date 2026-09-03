-- Durcissement RLS daily_volume / daily_order_book (audit SEV-024 / SEV-027).
-- Idempotent, non destructif (service_role BYPASSE la RLS → workers/app inchangés).

-- ── SEV-024 : daily_volume — RLS activée en PROD mais ABSENTE des migrations Git (dérive).
-- On la matérialise en Git (no-op en prod) + on RETIRE le GRANT ALL à anon/authenticated
-- (migration 20260609140721) : avec RLS activée sans policy, la table est déjà en deny-all,
-- mais laisser le GRANT est dangereux si la RLS était un jour désactivée. Deny-all explicite.
ALTER TABLE public.daily_volume ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.daily_volume FROM anon, authenticated;

-- ── SEV-027 : daily_order_book — policy `subscribed_users_read` basée sur auth.uid() qui est
-- TOUJOURS NULL (auth maison) → elle n'accorde JAMAIS l'accès (deny-all effectif) tout en
-- laissant croire à un gating commercial. On la RETIRE (trompeuse). L'accès légitime passe
-- déjà par service_role (bypass RLS) + le gating de palier est appliqué côté API (data-tier).
DROP POLICY IF EXISTS subscribed_users_read ON public.daily_order_book;

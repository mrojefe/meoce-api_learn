-- ============================================================================
-- account_kind : NATURE du compte, ORTHOGONALE à `role` (permissions).
--   'real' = vrai utilisateur (défaut).
--   'seed' = compte d'AMORÇAGE : anime la plateforme au lancement (scores
--            ckoissa, réactions articles, votes d'idées) AVANT l'arrivée des
--            vrais utilisateurs. Ne se connecte jamais (password_hash NULL).
-- Objectif : pouvoir EXCLURE ces comptes des vraies statistiques, les filtrer
-- partout, et les labelliser/convertir un jour. On ne TOUCHE PAS `role`
-- (user/admin/api_client) : un seed reste role='user'.
-- Additif pur, idempotent.
-- ============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS account_kind TEXT NOT NULL DEFAULT 'real';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_account_kind_check') THEN
    ALTER TABLE users ADD CONSTRAINT users_account_kind_check CHECK (account_kind IN ('real', 'seed'));
  END IF;
END $$;

-- Index partiel : on ne requête que les seed (minoritaires) — pour les exclure
-- des agrégats réels ou les lister.
CREATE INDEX IF NOT EXISTS users_account_kind_seed_idx ON users(account_kind) WHERE account_kind <> 'real';

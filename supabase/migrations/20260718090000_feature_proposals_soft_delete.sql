-- Soft delete des propositions de fonctionnalités (#158).
--
-- L'auteur d'une proposition doit pouvoir la retirer de l'affichage, MAIS la ligne est
-- CONSERVÉE en base — exigence explicite du fondateur. On n'utilise donc PAS la colonne
-- `status` : sa contrainte CHECK n'autorise que ('open','planned','in_progress','done',
-- 'rejected') et n'admet pas de valeur 'deleted'.
--
-- Suppression PHYSIQUE interdite : proposal_votes et proposal_attachments référencent
-- feature_proposals en ON DELETE CASCADE → un DELETE emporterait votes et pièces jointes.
--
-- Migration idempotente et non destructive : aucun DML, aucune donnée touchée.

ALTER TABLE feature_proposals
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

COMMENT ON COLUMN feature_proposals.deleted_at IS
  'Horodatage du soft delete par l''auteur. NULL = proposition visible. Non NULL = masquée de la liste, ligne conservée (votes et pièces jointes intacts).';

-- La liste ne lit que les propositions vivantes → index partiel sur le tri par date.
CREATE INDEX IF NOT EXISTS idx_feature_proposals_not_deleted
  ON feature_proposals(created_at)
  WHERE deleted_at IS NULL;

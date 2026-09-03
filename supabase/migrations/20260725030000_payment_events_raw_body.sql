-- ============================================================================
-- payment_events.raw_body — corps EXACT reçu du prestataire (texte brut)
--
-- Pourquoi une colonne de plus alors que `raw_payload` (JSONB) existe déjà :
-- la signature d'un webhook se calcule sur les OCTETS reçus. Or le JSONB
-- réordonne les clés et normalise la mise en forme : impossible de rejouer ou
-- d'auditer une signature à partir de lui. Sans le corps brut, on ne peut pas
-- prouver a posteriori qu'une notification était authentique — ni diagnostiquer
-- un refus de signature.
--
-- Additive et sans risque : colonne nullable, aucun impact sur l'existant.
-- Le ledger reste immuable (le trigger interdisant UPDATE/DELETE est conservé :
-- ALTER TABLE porte sur la structure, pas sur les lignes).
-- ============================================================================

ALTER TABLE public.payment_events
  ADD COLUMN IF NOT EXISTS raw_body TEXT;

COMMENT ON COLUMN public.payment_events.raw_body IS
  'Corps HTTP brut reçu, tel quel. Nécessaire pour recalculer/auditer la signature du webhook (le JSONB raw_payload ne conserve ni l''ordre des clés ni la mise en forme).';

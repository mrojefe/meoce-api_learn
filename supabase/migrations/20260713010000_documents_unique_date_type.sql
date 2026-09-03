-- La table `documents` a été généralisée (boc_documents → documents, type
-- discriminant ajouté) mais la contrainte UNIQUE(document_date) est restée
-- trop stricte : elle empêche un 2e type de document (ex: bridge_recommendation)
-- d'exister à la même date qu'un BOC. On la remplace par UNIQUE(document_date, type)
-- — c'était visiblement l'intention de la généralisation, restée incomplète.
-- Idempotent.
ALTER TABLE public.documents DROP CONSTRAINT IF EXISTS documents_document_date_key;
DO $$ BEGIN
  ALTER TABLE public.documents ADD CONSTRAINT documents_document_date_type_key UNIQUE (document_date, type);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

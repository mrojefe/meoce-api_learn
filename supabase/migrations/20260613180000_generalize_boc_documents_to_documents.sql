-- Migration : généralisation de boc_documents → documents
-- Objectif : la table peut accueillir n'importe quel type de document (BOC, rapport annuel, etc.)
-- Auteur : meoce — 2026-06-13
-- Idempotence (SEV-030) : tout le bloc de RENAME est gardé par « boc_documents existe
-- encore ». Si la table a déjà été renommée en `documents`, le bloc est entièrement sauté →
-- la migration est rejouable sans erreur (utile pour un reset de schéma).

BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'boc_documents'
  ) THEN
    -- 1. Renommer la table
    ALTER TABLE public.boc_documents RENAME TO documents;

    -- 2. Ajouter colonne type (discriminant)
    ALTER TABLE public.documents ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'boc';

    -- 3. Renommer boc_date → document_date
    ALTER TABLE public.documents RENAME COLUMN boc_date TO document_date;

    -- 4. Renommer les contraintes de documents
    ALTER TABLE public.documents RENAME CONSTRAINT boc_documents_pkey              TO documents_pkey;
    ALTER TABLE public.documents RENAME CONSTRAINT boc_documents_boc_date_key      TO documents_document_date_key;
    ALTER TABLE public.documents RENAME CONSTRAINT boc_documents_content_hash_key  TO documents_content_hash_key;
    ALTER TABLE public.documents RENAME CONSTRAINT boc_documents_file_hash_key     TO documents_file_hash_key;
    ALTER TABLE public.documents RENAME CONSTRAINT boc_documents_status_check      TO documents_status_check;

    -- 6. daily_order_book : renommer les colonnes boc_*
    ALTER TABLE public.daily_order_book RENAME COLUMN boc_document_id  TO document_id;
    ALTER TABLE public.daily_order_book RENAME COLUMN boc_format_model TO format_model;

    -- 7. Renommer la FK et son index
    ALTER TABLE public.daily_order_book
      RENAME CONSTRAINT daily_order_book_boc_document_id_fkey TO daily_order_book_document_id_fkey;

    ALTER INDEX public.idx_daily_order_book_boc_doc RENAME TO idx_daily_order_book_doc;
  END IF;
END $$;

COMMIT;

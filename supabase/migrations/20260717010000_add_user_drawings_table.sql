-- RATTRAPAGE DE DÉRIVE Git ↔ base (aucun changement fonctionnel attendu en prod).
--
-- Constat de l'audit, vérifié en base : la table `user_drawings` EXISTE en production
-- (avec son index, sa contrainte FK, sa RLS et sa policy) mais n'a JAMAIS eu de
-- migration — `grep -rn "user_drawings" supabase/migrations/` ne renvoyait rien. La
-- prod n'était donc reproductible par personne : une base reconstruite depuis les
-- migrations n'avait pas la table, et toute la route /api/user/drawings échouait.
--
-- Cette migration DÉCLARE l'existant, à l'identique de ce qui a été relevé par \d.
-- Elle est strictement IDEMPOTENTE et doit être un NO-OP sur la prod actuelle : elle
-- ne crée que ce qui manque et ne touche AUCUNE donnée (aucun DML).
--
-- Note importante sur `id` : la colonne est `uuid NOT NULL` SANS DEFAULT — l'id est
-- fourni par le client (le front génère un UUID). On conserve volontairement cette
-- absence de défaut pour rester fidèle à la prod ; c'est aussi ce qui a révélé la
-- panne de persistance (le front envoyait `draw_<timestamp>` → 22P02 → 500 avalé).

CREATE TABLE IF NOT EXISTS public.user_drawings (
  id         uuid        NOT NULL,
  user_id    uuid        NOT NULL,
  symbol     text        NOT NULL,
  payload    jsonb       NOT NULL,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_drawings_pkey PRIMARY KEY (id)
);

-- FK vers users(id) ON DELETE CASCADE (idempotent : pg_constraint testé explicitement,
-- ADD CONSTRAINT n'ayant pas de IF NOT EXISTS).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_drawings_user_id_fkey'
      AND conrelid = 'public.user_drawings'::regclass
  ) THEN
    ALTER TABLE public.user_drawings
      ADD CONSTRAINT user_drawings_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_user_drawings_user_symbol
  ON public.user_drawings USING btree (user_id, symbol);

-- RLS : ON + policy `own_all`. Les workers/API écrivent en service_role (BYPASSRLS),
-- donc non affectés. ENABLE ROW LEVEL SECURITY est idempotent.
ALTER TABLE public.user_drawings ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_drawings' AND policyname = 'own_all'
  ) THEN
    CREATE POLICY own_all ON public.user_drawings
      FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;

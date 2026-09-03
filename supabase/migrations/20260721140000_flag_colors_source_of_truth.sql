-- ============================================================================
-- flag_colors — SOURCE UNIQUE des couleurs de fanion (audit 2026-07-21)
--
-- Problème constaté : la palette vivait EN DUR dans le frontend
-- (useWatchlistFlags.FLAG_COLORS = 7 couleurs) tandis que la base n'en acceptait
-- que 5 via un CHECK figé :
--     CHECK (flag_color IN ('red','orange','yellow','green','blue'))
-- → un fanion violet ou rose était rejeté par la base. Deux listes, deux vérités,
--   divergence garantie (règle JF : « les couleurs possibles doivent être en BD,
--   pas de hardcode »).
--
-- Choix : une vraie TABLE de référence + CLÉ ÉTRANGÈRE (plutôt qu'un JSON dans
-- platform_config) afin que la validité soit garantie par l'intégrité référentielle
-- et que la liste n'existe QU'À UN SEUL ENDROIT. Ajouter une couleur = INSERT,
-- sans déploiement ni modification de code.
--
-- Idempotente. Ne touche AUCUNE donnée utilisateur (user_instrument_flags conserve
-- ses lignes ; la FK est simplement plus permissive que l'ancien CHECK).
-- ============================================================================

CREATE TABLE IF NOT EXISTS flag_colors (
  id         TEXT PRIMARY KEY,                    -- identifiant stable utilisé par l'app
  hex        TEXT        NOT NULL,                -- couleur d'affichage
  label      TEXT        NOT NULL,                -- libellé FR affiché à l'utilisateur
  sort_order INTEGER     NOT NULL DEFAULT 0,      -- ordre dans la palette
  is_active  BOOLEAN     NOT NULL DEFAULT TRUE,   -- retirer une couleur sans la supprimer
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Palette initiale = celle qui existait en dur dans le frontend (aucune régression
-- visuelle), violet et rose inclus — ils étaient proposés à l'utilisateur mais
-- refusés par la base.
INSERT INTO flag_colors (id, hex, label, sort_order) VALUES
  ('red',    '#ef4444', 'Rouge',  1),
  ('orange', '#f59e0b', 'Orange', 2),
  ('yellow', '#eab308', 'Jaune',  3),
  ('green',  '#22c55e', 'Vert',   4),
  ('blue',   '#3b82f6', 'Bleu',   5),
  ('purple', '#a855f7', 'Violet', 6),
  ('pink',   '#ec4899', 'Rose',   7)
ON CONFLICT (id) DO UPDATE
  SET hex = EXCLUDED.hex,
      label = EXCLUDED.label,
      sort_order = EXCLUDED.sort_order;

-- Remplace le CHECK figé par une FK vers la table de référence.
-- Le nom du CHECK peut varier selon l'historique → on le retrouve dynamiquement.
DO $$
DECLARE
  c_name TEXT;
BEGIN
  SELECT con.conname INTO c_name
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  WHERE rel.relname = 'user_instrument_flags'
    AND con.contype = 'c'
    AND pg_get_constraintdef(con.oid) ILIKE '%flag_color%'
  LIMIT 1;

  IF c_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE user_instrument_flags DROP CONSTRAINT %I', c_name);
  END IF;
END $$;

-- FK (ON UPDATE CASCADE : renommer un id de couleur propage aux fanions existants).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_instrument_flags_flag_color_fkey'
  ) THEN
    ALTER TABLE user_instrument_flags
      ADD CONSTRAINT user_instrument_flags_flag_color_fkey
      FOREIGN KEY (flag_color) REFERENCES flag_colors(id) ON UPDATE CASCADE;
  END IF;
END $$;

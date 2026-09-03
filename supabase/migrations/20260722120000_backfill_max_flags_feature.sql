-- ============================================================================
-- Backfill : features.max_flags manquait de la version versionnée (migrations)
--
-- Audit 2026-07-22 (verrous/plans custom) : la ligne `max_flags` existe et
-- fonctionne en prod (créée manuellement le 2026-07-11), mais AUCUNE migration
-- versionnée ne la crée — un environnement neuf reconstruit depuis les
-- migrations n'aurait pas cette clé, et get_user_entitlements ne la
-- renverrait jamais (le RPC ne connaît que les clés de `features`).
--
-- Idempotente (ON CONFLICT DO NOTHING) : ne touche pas la ligne existante en
-- prod, ne fait que garantir sa présence sur tout environnement reconstruit
-- depuis zéro.
-- ============================================================================

INSERT INTO features (key, label, description, kind, free_default, anon_default, category, display_order)
VALUES (
  'max_flags',
  'Flags / marqueurs',
  'Nombre de flags (arrow-up/down) par symbole (null = illimité)',
  'limit',
  '1'::jsonb,
  '1'::jsonb,
  'chart',
  46
)
ON CONFLICT (key) DO NOTHING;

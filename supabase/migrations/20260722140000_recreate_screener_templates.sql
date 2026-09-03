-- ============================================================================
-- screener_templates — resurrection (audit plans custom 2026-07-22)
--
-- La table existait dans le schéma initial (20260517130240) mais a été
-- supprimée le 2026-07-16 (20260716040000_drop_orphan_customization_tables)
-- car ORPHELINE : aucune route/UI ne l'utilisait, alors même que la clé
-- d'entitlement `max_screener_saves` existe et s'affiche déjà (SettingsModal)
-- sans qu'aucune fonctionnalité réelle n'y soit branchée.
--
-- Version simplifiée par rapport à l'originale : retire la colonne
-- `action_id` (couplage à `ivi_actions`, non nécessaire pour un simple
-- préréglage de filtres nommé) et `is_public` (pas de partage prévu pour
-- l'instant — ajoutable plus tard sans migration destructive).
-- ============================================================================

CREATE TABLE IF NOT EXISTS screener_templates (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       TEXT        NOT NULL,
  criteria   JSONB       NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_screener_templates_user ON screener_templates(user_id);

DROP TRIGGER IF EXISTS trg_screener_templates_updated_at ON screener_templates;
CREATE TRIGGER trg_screener_templates_updated_at
  BEFORE UPDATE ON screener_templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE screener_templates ENABLE ROW LEVEL SECURITY;

-- Dormante (auth maison, pas Supabase Auth) mais posée par cohérence avec le
-- reste du schéma — isolation réelle via service_role + filtre user_id côté API.
DROP POLICY IF EXISTS own_all ON screener_templates;
CREATE POLICY own_all ON screener_templates
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

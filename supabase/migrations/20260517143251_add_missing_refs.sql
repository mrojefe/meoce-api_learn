-- ============================================================
-- D126 — Ajout des références manquantes pour migration data
-- depuis Afriview_old (dmhsthfyubbhixeceslg)
-- ============================================================
-- 3 pays UEMOA + 2 secteurs supplémentaires.
-- BENCHMARK (sector old.id=8) sera mappé vers 'OTH' côté script Python
-- de migration data — on se base sur type='index' pour identifier les indices.
-- ============================================================

INSERT INTO countries (code, name, region, primary_currency_code) VALUES
  ('NE', 'Niger', 'West Africa', 'XOF'),
  ('TG', 'Togo',  'West Africa', 'XOF'),
  ('BJ', 'Bénin', 'West Africa', 'XOF');

INSERT INTO sectors (name, code) VALUES
  ('telecommunications',     'TLC'),
  ('consumer_discretionary', 'CSD');

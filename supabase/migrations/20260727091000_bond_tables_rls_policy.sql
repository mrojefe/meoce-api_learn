-- Complète la correction de 20260727090000 : `bond_details`/`bond_candles`
-- ont RLS ACTIVÉE (`relrowsecurity = true`) mais AUCUNE policy — vérifié en
-- base (`SELECT * FROM pg_policies WHERE tablename IN (...)` → 0 ligne),
-- alors que la migration d'origine (20260529200000) prévoyait une policy
-- `read_all USING (true)`. Le schéma live a manifestement divergé de ce
-- fichier (colonnes de `bond_candles` différentes aussi — table recréée
-- directement par un script d'import, pas via cette migration). Sans
-- policy, RLS activée = verrou total même avec le GRANT SELECT : ni anon ni
-- authenticated ne peuvent lire une seule ligne.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'bond_details'
  ) THEN
    CREATE POLICY read_all ON public.bond_details FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'bond_candles'
  ) THEN
    CREATE POLICY read_all ON public.bond_candles FOR SELECT USING (true);
  END IF;
END $$;

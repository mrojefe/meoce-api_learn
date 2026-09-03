-- ⚠️ MIGRATION RECONSTITUÉE (2026-07-25) — le fichier d'origine n'a JAMAIS été
-- commité : la migration avait été appliquée directement en production et
-- `schema_migrations` la référençait sans qu'aucun fichier n'existe. L'audit du
-- 2026-07-25 a relevé 15 versions dans ce cas — une reconstruction de la base
-- depuis les migrations aurait produit un schéma DIFFÉRENT de la production.
--
-- Contenu déduit du schéma RÉEL en production, pas du texte d'origine. Écrit de
-- façon IDEMPOTENTE : sans effet sur la prod (version déjà enregistrée), correct
-- sur une base reconstruite de zéro.

-- Pendant du bornage intraday, côté données journalières : l'accès anonyme
-- direct est retiré (la profondeur autorisée est arbitrée par l'API via
-- l'entitlement `history_years_max`, pas par une policy figée).
DO $do$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['daily_candles','daily_volume','daily_order_book'] LOOP
    IF to_regclass('public.'||t) IS NOT NULL THEN
      EXECUTE format('REVOKE SELECT ON public.%I FROM anon', t);
    END IF;
  END LOOP;
END $do$;

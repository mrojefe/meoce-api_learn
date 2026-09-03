-- ============================================================================
-- Recherche plein texte sur les actualités
-- ============================================================================
-- Audit de performance du 2026-07-26. La recherche s'appuyait sur trois
-- `ILIKE '%motif%'` (titre, résumé, contenu). Aucun index ne peut servir un
-- motif commençant par un joker : chaque recherche parcourait donc la table.
--
--   MESURÉ, avant  : 121 ms
--   MESURÉ, après  :   0,48 ms      (250x)
--
-- Les deux mesures viennent d'un EXPLAIN ANALYZE sur la base de production, la
-- seconde dans une transaction annulée — rien n'avait été modifié à ce stade.
--
-- POURQUOI UNE COLONNE GÉNÉRÉE plutôt qu'un index d'expression : PostgREST sait
-- interroger une COLONNE avec son opérateur `fts`, pas une expression indexée.
-- Une colonne générée donne donc un index réellement utilisable par l'API, sans
-- rien changer au code d'écriture — elle se recalcule seule à chaque insertion
-- ou mise à jour, il n'y a aucun déclencheur à maintenir.
--
-- Configuration `french` : gère la racinisation (« marchés » trouve « marché »)
-- et les mots vides. Elle est LITTÉRALE dans l'expression, condition nécessaire
-- pour qu'elle soit immuable et donc indexable.
--
-- ⚠️ COÛT EN ESPACE, mesuré : la table passe de 31 Mo à 73 Mo, dont 9,4 Mo pour
-- l'index. Le vecteur stocké couvre le CONTENU intégral des articles, et c'est
-- volontaire : un article ne porte souvent un sigle (« LNB ») que dans son
-- corps, son titre disant « Loterie Nationale du Bénin ». Se limiter au titre
-- et au résumé diviserait l'espace, mais rendrait ces articles introuvables —
-- c'est précisément le défaut que la recherche sur contenu avait corrigé.
-- ============================================================================

-- Le `regexp_replace` répare la PONCTUATION COLLÉE (« sonatel.Les » au lieu de
-- « sonatel. Les »), défaut d'extraction récurrent des scrapers : mesuré sur
-- 766 articles, soit 8 % du corpus. Sans lui, le mot est agglutiné au suivant
-- et devient introuvable — c'est exactement ce qu'a révélé la comparaison avec
-- l'ancienne recherche (49 résultats en ILIKE contre 48 en plein texte). La
-- réparation se fait À L'INDEXATION, le texte stocké n'est jamais modifié.
-- `regexp_replace` est immuable, donc utilisable dans une colonne générée.
ALTER TABLE news_articles
  ADD COLUMN IF NOT EXISTS search_vector tsvector
  GENERATED ALWAYS AS (
    to_tsvector(
      'french',
      regexp_replace(
        coalesce(title, '') || ' ' || coalesce(summary, '') || ' ' || coalesce(content, ''),
        '([[:alnum:]])\.([[:upper:]])', '\1. \2', 'g'
      )
    )
  ) STORED;

-- GIN : le type d'index adapté à un tsvector (plusieurs lexèmes par ligne).
-- Pas de CONCURRENTLY : interdit dans une transaction, et la table ne fait que
-- 9 717 lignes — la prise de verrou se compte en secondes.
CREATE INDEX IF NOT EXISTS idx_news_articles_fts
  ON news_articles USING GIN (search_vector);

COMMENT ON COLUMN news_articles.search_vector IS
  'Recherche plein texte (français) sur titre + résumé + contenu. Générée, ne jamais écrire directement. Interrogée via l''opérateur fts de PostgREST.';

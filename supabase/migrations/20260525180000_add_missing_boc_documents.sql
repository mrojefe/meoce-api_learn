-- Migration: Ajout des 16 entrées boc_documents manquantes
-- Ces BOC existent localement et dans Minio (raw/boc_brvm/) mais n'étaient pas
-- enregistrés dans boc_documents. Détectés via GOLD_ACTION_ORDERBOOK (578 lignes
-- sans boc_document_id sur 16 dates distinctes).
-- source_url : pattern abidjan.net utilisé pour les BOC historiques
-- file_hash  : SHA-256 du fichier PDF local

INSERT INTO boc_documents (id, boc_date, source_url, r2_key, file_hash, status, page_count)
VALUES
  (gen_random_uuid(), '2010-04-16', 'https://media-files.abidjan.net/document/docs/BOC-20100416.pdf', 'raw/boc_brvm/BOC_20100416.pdf', '8b3d09bcfc8bd349283c4d237e49b3eabbc7075deeb1f6fd70cd521b5e63b171', 'processed', 6),
  (gen_random_uuid(), '2010-04-21', 'https://media-files.abidjan.net/document/docs/BOC-20100421.pdf', 'raw/boc_brvm/BOC_20100421.pdf', '4e3dfcd40a621818c41c3d6c7d798e53b5291be36067a4d56b042f56ce4a5438', 'processed', 6),
  (gen_random_uuid(), '2010-05-14', 'https://media-files.abidjan.net/document/docs/BOC-20100514.pdf', 'raw/boc_brvm/BOC_20100514.pdf', 'd315ee79028695ebc727d9b199379149c175f69c0606bf51bf9ff4a178c00ac3', 'processed', 6),
  (gen_random_uuid(), '2010-05-21', 'https://media-files.abidjan.net/document/docs/BOC-20100521.pdf', 'raw/boc_brvm/BOC_20100521.pdf', '78a06b0f0656f4517c8c00ef9d8ba8ed611fec9ed46990afb2e92c75b8bc325a', 'processed', 6),
  (gen_random_uuid(), '2010-11-24', 'https://media-files.abidjan.net/document/docs/BOC-20101124.pdf', 'raw/boc_brvm/BOC_20101124.pdf', '042b5b62696915f85c1067040ad08df14e47098e34daf696c0df4cc301efc1cb', 'processed', 6),
  (gen_random_uuid(), '2010-12-17', 'https://media-files.abidjan.net/document/docs/BOC-20101217.pdf', 'raw/boc_brvm/BOC_20101217.pdf', 'ad94954ae9dce11963e98bea46209432de708377549ad27ed1d1bee535eb43d1', 'processed', 3),
  (gen_random_uuid(), '2010-12-24', 'https://media-files.abidjan.net/document/docs/BOC-20101224.pdf', 'raw/boc_brvm/BOC_20101224.pdf', 'e91b48232f1d1b1b1764e3234757dde0d409b16c2b6d42fd80e1924c956aceaf', 'processed', 7),
  (gen_random_uuid(), '2010-12-30', 'https://media-files.abidjan.net/document/docs/BOC-20101230.pdf', 'raw/boc_brvm/BOC_20101230.pdf', '098ff072125670bd74cc0a0635c22d9839d9e0a45a4d15a81ec660564f8b094b', 'processed', 6),
  (gen_random_uuid(), '2011-05-11', 'https://media-files.abidjan.net/document/docs/BOC-20110511.pdf', 'raw/boc_brvm/BOC_20110511.pdf', '0f3e37e9ac6d263598532c561600b22ccdc5c2cd445b4c9a09768f0ec6455c32', 'processed', 6),
  (gen_random_uuid(), '2011-05-12', 'https://media-files.abidjan.net/document/docs/BOC-20110512.pdf', 'raw/boc_brvm/BOC_20110512.pdf', '5a0c56bb2a67c6633dfddc5818cf304dd606fdf394cd3a5e88eefad090eaccc6', 'processed', 4),
  (gen_random_uuid(), '2011-07-14', 'https://media-files.abidjan.net/document/docs/BOC-20110714.pdf', 'raw/boc_brvm/BOC_20110714.pdf', '8501aa57e76d244062bce0df24580e59e5d75b3e110b120e731069d5e294aa77', 'processed', 3),
  (gen_random_uuid(), '2011-07-25', 'https://media-files.abidjan.net/document/docs/BOC-20110725.pdf', 'raw/boc_brvm/BOC_20110725.pdf', 'd01e0ef3aebe929f9f1b40158c6b408507bf112f85a9a2521b3dc06e6856895f', 'processed', 3),
  (gen_random_uuid(), '2011-08-11', 'https://media-files.abidjan.net/document/docs/BOC-20110811.pdf', 'raw/boc_brvm/BOC_20110811.pdf', 'b39bb7d32ba5ad837127ae81df4c2e0bfa567f6b2a0b01ef94f333d68d5dba72', 'processed', 3),
  (gen_random_uuid(), '2011-08-31', 'https://media-files.abidjan.net/document/docs/BOC-20110831.pdf', 'raw/boc_brvm/BOC_20110831.pdf', '03ab7d8cbbef16663533c08467a9db1b9615ab62ba4ec6b8eaa22ee79d94e632', 'processed', 3),
  (gen_random_uuid(), '2011-12-09', 'https://media-files.abidjan.net/document/docs/BOC-20111209.pdf', 'raw/boc_brvm/BOC_20111209.pdf', '22b9c0bd4045df5d3041a323428cfbf8d498ba813a4bdba3aed3df76469747fb', 'processed', 3),
  (gen_random_uuid(), '2021-05-03', 'https://media-files.abidjan.net/document/docs/BOC-20210503.pdf', 'raw/boc_brvm/BOC_20210503.pdf', 'bbc25a4d3f3aece66d7fb24d986e9d8a0d3bf1b8e918afe763f19d31d67e2452', 'processed', 14)
ON CONFLICT DO NOTHING;

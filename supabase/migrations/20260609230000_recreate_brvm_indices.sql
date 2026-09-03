-- Migration pour purger et recréer proprement les 11 indices officiels de la BRVM.
-- Grâce au ON DELETE CASCADE sur la foreign key de daily_candles et daily_volume,
-- la suppression des indices de la table public.instruments supprime automatiquement
-- toutes leurs bougies historiques correspondantes.

-- 1. Suppression des anciens indices existants
DELETE FROM public.instruments WHERE type = 'index';

-- 2. Insertion des 11 indices officiels
INSERT INTO public.instruments (id, exchange_id, symbol, name, type, currency_code, sector_id, country_code, status)
VALUES
    ('2466d76e-1660-4c8b-a999-7689837d5fce', 1, 'BRVM-30', 'BRVM Index 30', 'index', 'XOF', 7, 'CI', 'active'),
    ('e622e7f1-5c9a-42b7-b193-bf276eefe5f2', 1, 'BRVMC', 'BRVM Composite', 'index', 'XOF', 7, 'CI', 'active'),
    ('4a93d8d3-377b-4d1c-a3f3-6840d224e91f', 1, 'BRVMPR', 'BRVM Prestige', 'index', 'XOF', 7, 'CI', 'active'),
    ('5f1a0ec6-b92c-47d1-8a0b-2ec5b7e45eab', 1, 'BRVMPA', 'BRVM Principal', 'index', 'XOF', 7, 'CI', 'active'),
    ('12c0da61-8ce0-42ec-9174-ad8104ea7d24', 1, 'BRVM-CB', 'BRVM Consommation de Base', 'index', 'XOF', 10, 'CI', 'active'),
    ('cc120c25-eb18-4e15-a6df-ab9ed37ed5ce', 1, 'BRVM-CD', 'BRVM Consommation Discrétionnaire', 'index', 'XOF', 9, 'CI', 'active'),
    ('f0d68345-d6fb-451f-8634-f0230e148ef1', 1, 'BRVM-EN', 'BRVM Énergie', 'index', 'XOF', 11, 'CI', 'active'),
    ('b9e803f8-9c37-4bfe-88f8-364894f3244d', 1, 'BRVM-IN', 'BRVM Industriels', 'index', 'XOF', 2, 'CI', 'active'),
    ('414fa5b3-5bb1-4932-baaa-63f841af822d', 1, 'BRVM-SF', 'BRVM Services Financiers', 'index', 'XOF', 1, 'CI', 'active'),
    ('557ba8d3-7d31-482f-8703-a1c0de98b3c6', 1, 'BRVM-SP', 'BRVM Services Publics', 'index', 'XOF', 5, 'CI', 'active'),
    ('e8add5a0-270f-454d-bd92-050a05eedfb5', 1, 'BRVM-TEL', 'BRVM Télécommunications', 'index', 'XOF', 8, 'CI', 'active');

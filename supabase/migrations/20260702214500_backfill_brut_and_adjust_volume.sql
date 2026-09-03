-- Backfill des colonnes _brut (daily_candles) et correction de quantity vers
-- la convention ajustée (daily_volume), sur la base des ratios de splits
-- detectes via comparaison avec Richbourse (cours_ajuste/cours_normal).
--
-- Etape 1 : valeurs par defaut (aucun split connu => brut = ajuste).
-- Etape 2 : corrections ciblees par instrument/plage de dates/ratio,
--           pour les symboles ayant un historique de splits confirme.

-- === ETAPE 1 : valeurs par defaut ===
UPDATE public.daily_candles SET
  open_price_brut = open_price,
  high_price_brut = high_price,
  low_price_brut = low_price,
  close_price_brut = close_price
WHERE open_price_brut IS NULL;

UPDATE public.daily_volume SET quantity_brut = quantity
WHERE quantity_brut IS NULL;

-- === ETAPE 2 : corrections par regime (ratio != 1) ===
-- ABJC (2000-03-31 -> 2016-09-29) : ratio x20.0  [1409 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 20.0, high_price_brut = high_price * 20.0, low_price_brut = low_price * 20.0, close_price_brut = close_price * 20.0 WHERE instrument_id = '5d516493-3364-40b7-a892-40326b49de00' AND date >= '2000-03-31' AND date <= '2016-09-29';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 20.0) WHERE instrument_id = '5d516493-3364-40b7-a892-40326b49de00' AND date >= '2000-03-31' AND date <= '2016-09-29';

-- BICC (1998-09-16 -> 2017-10-05) : ratio x10.0  [2118 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 10.0, high_price_brut = high_price * 10.0, low_price_brut = low_price * 10.0, close_price_brut = close_price * 10.0 WHERE instrument_id = 'a93a5e4f-e355-4825-8d49-0eacdf3ff8f6' AND date >= '1998-09-16' AND date <= '2017-10-05';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 10.0) WHERE instrument_id = 'a93a5e4f-e355-4825-8d49-0eacdf3ff8f6' AND date >= '1998-09-16' AND date <= '2017-10-05';

-- BNBC (1998-09-18 -> 2017-07-25) : ratio x20.0  [1417 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 20.0, high_price_brut = high_price * 20.0, low_price_brut = low_price * 20.0, close_price_brut = close_price * 20.0 WHERE instrument_id = '3224f148-8b0c-4e50-b3b9-ad19ee963992' AND date >= '1998-09-18' AND date <= '2017-07-25';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 20.0) WHERE instrument_id = '3224f148-8b0c-4e50-b3b9-ad19ee963992' AND date >= '1998-09-18' AND date <= '2017-07-25';

-- BOAB (2000-11-17 -> 2017-06-19) : ratio x40.0287  [3145 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 40.0287, high_price_brut = high_price * 40.0287, low_price_brut = low_price * 40.0287, close_price_brut = close_price * 40.0287 WHERE instrument_id = 'c19c9d32-bfbe-4c7d-924b-93b28b0bea07' AND date >= '2000-11-17' AND date <= '2017-06-19';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 40.0287) WHERE instrument_id = 'c19c9d32-bfbe-4c7d-924b-93b28b0bea07' AND date >= '2000-11-17' AND date <= '2017-06-19';

-- BOAB (2017-06-20 -> 2017-10-30) : ratio x20.0131  [88 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 20.0131, high_price_brut = high_price * 20.0131, low_price_brut = low_price * 20.0131, close_price_brut = close_price * 20.0131 WHERE instrument_id = 'c19c9d32-bfbe-4c7d-924b-93b28b0bea07' AND date >= '2017-06-20' AND date <= '2017-10-30';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 20.0131) WHERE instrument_id = 'c19c9d32-bfbe-4c7d-924b-93b28b0bea07' AND date >= '2017-06-20' AND date <= '2017-10-30';

-- BOAB (2017-10-31 -> 2024-09-02) : ratio x2.0012  [1695 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 2.0012, high_price_brut = high_price * 2.0012, low_price_brut = low_price * 2.0012, close_price_brut = close_price * 2.0012 WHERE instrument_id = 'c19c9d32-bfbe-4c7d-924b-93b28b0bea07' AND date >= '2017-10-31' AND date <= '2024-09-02';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 2.0012) WHERE instrument_id = 'c19c9d32-bfbe-4c7d-924b-93b28b0bea07' AND date >= '2017-10-31' AND date <= '2024-09-02';

-- BOABF (2011-01-03 -> 2017-06-23) : ratio x40.0  [1170 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 40.0, high_price_brut = high_price * 40.0, low_price_brut = low_price * 40.0, close_price_brut = close_price * 40.0 WHERE instrument_id = 'f4e99627-43ca-4ac4-b56f-8978f1b70a59' AND date >= '2011-01-03' AND date <= '2017-06-23';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 40.0) WHERE instrument_id = 'f4e99627-43ca-4ac4-b56f-8978f1b70a59' AND date >= '2011-01-03' AND date <= '2017-06-23';

-- BOABF (2017-06-27 -> 2017-10-23) : ratio x20.0  [77 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 20.0, high_price_brut = high_price * 20.0, low_price_brut = low_price * 20.0, close_price_brut = close_price * 20.0 WHERE instrument_id = 'f4e99627-43ca-4ac4-b56f-8978f1b70a59' AND date >= '2017-06-27' AND date <= '2017-10-23';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 20.0) WHERE instrument_id = 'f4e99627-43ca-4ac4-b56f-8978f1b70a59' AND date >= '2017-06-27' AND date <= '2017-10-23';

-- BOABF (2017-10-24 -> 2024-08-27) : ratio x2.0  [1675 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 2.0, high_price_brut = high_price * 2.0, low_price_brut = low_price * 2.0, close_price_brut = close_price * 2.0 WHERE instrument_id = 'f4e99627-43ca-4ac4-b56f-8978f1b70a59' AND date >= '2017-10-24' AND date <= '2024-08-27';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 2.0) WHERE instrument_id = 'f4e99627-43ca-4ac4-b56f-8978f1b70a59' AND date >= '2017-10-24' AND date <= '2024-08-27';

-- BOAC (2010-04-12 -> 2017-06-19) : ratio x40.0  [1243 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 40.0, high_price_brut = high_price * 40.0, low_price_brut = low_price * 40.0, close_price_brut = close_price * 40.0 WHERE instrument_id = '1caa08b2-c742-4268-9c04-f592c54c6c59' AND date >= '2010-04-12' AND date <= '2017-06-19';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 40.0) WHERE instrument_id = '1caa08b2-c742-4268-9c04-f592c54c6c59' AND date >= '2010-04-12' AND date <= '2017-06-19';

-- BOAC (2017-06-21 -> 2017-10-25) : ratio x20.0  [82 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 20.0, high_price_brut = high_price * 20.0, low_price_brut = low_price * 20.0, close_price_brut = close_price * 20.0 WHERE instrument_id = '1caa08b2-c742-4268-9c04-f592c54c6c59' AND date >= '2017-06-21' AND date <= '2017-10-25';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 20.0) WHERE instrument_id = '1caa08b2-c742-4268-9c04-f592c54c6c59' AND date >= '2017-06-21' AND date <= '2017-10-25';

-- BOAC (2017-10-26 -> 2024-10-24) : ratio x2.0  [1732 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 2.0, high_price_brut = high_price * 2.0, low_price_brut = low_price * 2.0, close_price_brut = close_price * 2.0 WHERE instrument_id = '1caa08b2-c742-4268-9c04-f592c54c6c59' AND date >= '2017-10-26' AND date <= '2024-10-24';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 2.0) WHERE instrument_id = '1caa08b2-c742-4268-9c04-f592c54c6c59' AND date >= '2017-10-26' AND date <= '2024-10-24';

-- BOAM (2016-05-31 -> 2017-09-19) : ratio x11.2656  [324 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 11.2656, high_price_brut = high_price * 11.2656, low_price_brut = low_price * 11.2656, close_price_brut = close_price * 11.2656 WHERE instrument_id = '638657c2-535a-479e-84de-809435a3354b' AND date >= '2016-05-31' AND date <= '2017-09-19';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 11.2656) WHERE instrument_id = '638657c2-535a-479e-84de-809435a3354b' AND date >= '2016-05-31' AND date <= '2017-09-19';

-- BOAM (2017-09-20 -> 2017-12-21) : ratio x7.5095  [62 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 7.5095, high_price_brut = high_price * 7.5095, low_price_brut = low_price * 7.5095, close_price_brut = close_price * 7.5095 WHERE instrument_id = '638657c2-535a-479e-84de-809435a3354b' AND date >= '2017-09-20' AND date <= '2017-12-21';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 7.5095) WHERE instrument_id = '638657c2-535a-479e-84de-809435a3354b' AND date >= '2017-09-20' AND date <= '2017-12-21';

-- BOAM (2017-12-22 -> 2024-08-27) : ratio x1.5019  [1647 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 1.5019, high_price_brut = high_price * 1.5019, low_price_brut = low_price * 1.5019, close_price_brut = close_price * 1.5019 WHERE instrument_id = '638657c2-535a-479e-84de-809435a3354b' AND date >= '2017-12-22' AND date <= '2024-08-27';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 1.5019) WHERE instrument_id = '638657c2-535a-479e-84de-809435a3354b' AND date >= '2017-12-22' AND date <= '2024-08-27';

-- BOAN (2003-12-30 -> 2017-06-20) : ratio x20.8178  [1865 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 20.8178, high_price_brut = high_price * 20.8178, low_price_brut = low_price * 20.8178, close_price_brut = close_price * 20.8178 WHERE instrument_id = '0b6ba856-914e-4c87-97f5-e02d70bdca4a' AND date >= '2003-12-30' AND date <= '2017-06-20';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 20.8178) WHERE instrument_id = '0b6ba856-914e-4c87-97f5-e02d70bdca4a' AND date >= '2003-12-30' AND date <= '2017-06-20';

-- BOAN (2017-06-21 -> 2017-10-26) : ratio x16.0118  [79 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 16.0118, high_price_brut = high_price * 16.0118, low_price_brut = low_price * 16.0118, close_price_brut = close_price * 16.0118 WHERE instrument_id = '0b6ba856-914e-4c87-97f5-e02d70bdca4a' AND date >= '2017-06-21' AND date <= '2017-10-26';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 16.0118) WHERE instrument_id = '0b6ba856-914e-4c87-97f5-e02d70bdca4a' AND date >= '2017-06-21' AND date <= '2017-10-26';

-- BOAN (2017-10-27 -> 2024-09-03) : ratio x1.6012  [1681 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 1.6012, high_price_brut = high_price * 1.6012, low_price_brut = low_price * 1.6012, close_price_brut = close_price * 1.6012 WHERE instrument_id = '0b6ba856-914e-4c87-97f5-e02d70bdca4a' AND date >= '2017-10-27' AND date <= '2024-09-03';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 1.6012) WHERE instrument_id = '0b6ba856-914e-4c87-97f5-e02d70bdca4a' AND date >= '2017-10-27' AND date <= '2024-09-03';

-- BOAS (2014-12-10 -> 2017-06-23) : ratio x30.0153  [618 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 30.0153, high_price_brut = high_price * 30.0153, low_price_brut = low_price * 30.0153, close_price_brut = close_price * 30.0153 WHERE instrument_id = '660510aa-e1a0-4037-97cf-8b383fb9fa80' AND date >= '2014-12-10' AND date <= '2017-06-23';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 30.0153) WHERE instrument_id = '660510aa-e1a0-4037-97cf-8b383fb9fa80' AND date >= '2014-12-10' AND date <= '2017-06-23';

-- BOAS (2017-06-27 -> 2017-10-27) : ratio x15.0075  [86 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 15.0075, high_price_brut = high_price * 15.0075, low_price_brut = low_price * 15.0075, close_price_brut = close_price * 15.0075 WHERE instrument_id = '660510aa-e1a0-4037-97cf-8b383fb9fa80' AND date >= '2017-06-27' AND date <= '2017-10-27';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 15.0075) WHERE instrument_id = '660510aa-e1a0-4037-97cf-8b383fb9fa80' AND date >= '2017-06-27' AND date <= '2017-10-27';

-- BOAS (2017-10-30 -> 2024-08-28) : ratio x1.5009  [1690 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 1.5009, high_price_brut = high_price * 1.5009, low_price_brut = low_price * 1.5009, close_price_brut = close_price * 1.5009 WHERE instrument_id = '660510aa-e1a0-4037-97cf-8b383fb9fa80' AND date >= '2017-10-30' AND date <= '2024-08-28';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 1.5009) WHERE instrument_id = '660510aa-e1a0-4037-97cf-8b383fb9fa80' AND date >= '2017-10-30' AND date <= '2024-08-28';

-- CABC (1998-09-16 -> 2017-08-11) : ratio x40.0  [1363 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 40.0, high_price_brut = high_price * 40.0, low_price_brut = low_price * 40.0, close_price_brut = close_price * 40.0 WHERE instrument_id = '74a8631f-5b95-4d33-8e3c-812ce772c808' AND date >= '1998-09-16' AND date <= '2017-08-11';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 40.0) WHERE instrument_id = '74a8631f-5b95-4d33-8e3c-812ce772c808' AND date >= '1998-09-16' AND date <= '2017-08-11';

-- CBIBF (2016-12-23 -> 2017-09-20) : ratio x5.1205  [184 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 5.1205, high_price_brut = high_price * 5.1205, low_price_brut = low_price * 5.1205, close_price_brut = close_price * 5.1205 WHERE instrument_id = 'd3fd71f2-6492-4ac5-a0a0-9e8307faae30' AND date >= '2016-12-23' AND date <= '2017-09-20';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 5.1205) WHERE instrument_id = 'd3fd71f2-6492-4ac5-a0a0-9e8307faae30' AND date >= '2016-12-23' AND date <= '2017-09-20';

-- CBIBF (2017-09-21 -> 2017-12-13) : ratio x5.0  [56 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 5.0, high_price_brut = high_price * 5.0, low_price_brut = low_price * 5.0, close_price_brut = close_price * 5.0 WHERE instrument_id = 'd3fd71f2-6492-4ac5-a0a0-9e8307faae30' AND date >= '2017-09-21' AND date <= '2017-12-13';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 5.0) WHERE instrument_id = 'd3fd71f2-6492-4ac5-a0a0-9e8307faae30' AND date >= '2017-09-21' AND date <= '2017-12-13';

-- CFAC (1998-09-18 -> 2017-12-12) : ratio x100.0  [1200 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 100.0, high_price_brut = high_price * 100.0, low_price_brut = low_price * 100.0, close_price_brut = close_price * 100.0 WHERE instrument_id = '59cf93cf-8278-4150-9903-6a178c34466e' AND date >= '1998-09-18' AND date <= '2017-12-12';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 100.0) WHERE instrument_id = '59cf93cf-8278-4150-9903-6a178c34466e' AND date >= '1998-09-18' AND date <= '2017-12-12';

-- CIEC (1998-09-16 -> 2017-10-18) : ratio x20.0  [3231 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 20.0, high_price_brut = high_price * 20.0, low_price_brut = low_price * 20.0, close_price_brut = close_price * 20.0 WHERE instrument_id = '0b160244-c4b6-46ce-a353-b158b518a22c' AND date >= '1998-09-16' AND date <= '2017-10-18';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 20.0) WHERE instrument_id = '0b160244-c4b6-46ce-a353-b158b518a22c' AND date >= '1998-09-16' AND date <= '2017-10-18';

-- ECOC (2017-12-12 -> 2018-12-26) : ratio x5.0  [254 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 5.0, high_price_brut = high_price * 5.0, low_price_brut = low_price * 5.0, close_price_brut = close_price * 5.0 WHERE instrument_id = '99096eeb-0b17-4bab-86e6-7c8dff029bac' AND date >= '2017-12-12' AND date <= '2018-12-26';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 5.0) WHERE instrument_id = '99096eeb-0b17-4bab-86e6-7c8dff029bac' AND date >= '2017-12-12' AND date <= '2018-12-26';

-- ETIT (2006-09-11 -> 2008-06-06) : ratio x5.0  [408 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 5.0, high_price_brut = high_price * 5.0, low_price_brut = low_price * 5.0, close_price_brut = close_price * 5.0 WHERE instrument_id = 'b235abb6-0b78-44e2-8b60-a8f80c3b457c' AND date >= '2006-09-11' AND date <= '2008-06-06';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 5.0) WHERE instrument_id = 'b235abb6-0b78-44e2-8b60-a8f80c3b457c' AND date >= '2006-09-11' AND date <= '2008-06-06';

-- FTSC (1998-09-16 -> 2018-01-30) : ratio x4.0  [2928 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 4.0, high_price_brut = high_price * 4.0, low_price_brut = low_price * 4.0, close_price_brut = close_price * 4.0 WHERE instrument_id = '00bffb07-638e-4e43-a723-ea4a70acfb14' AND date >= '1998-09-16' AND date <= '2018-01-30';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 4.0) WHERE instrument_id = '00bffb07-638e-4e43-a723-ea4a70acfb14' AND date >= '1998-09-16' AND date <= '2018-01-30';

-- NEIC (2000-04-14 -> 2017-08-09) : ratio x25.0  [424 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 25.0, high_price_brut = high_price * 25.0, low_price_brut = low_price * 25.0, close_price_brut = close_price * 25.0 WHERE instrument_id = 'e75df91d-bebe-4f13-adfd-59d4485b9b2b' AND date >= '2000-04-14' AND date <= '2017-08-09';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 25.0) WHERE instrument_id = 'e75df91d-bebe-4f13-adfd-59d4485b9b2b' AND date >= '2000-04-14' AND date <= '2017-08-09';

-- NTLC (1998-09-18 -> 2017-09-07) : ratio x20.0  [1783 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 20.0, high_price_brut = high_price * 20.0, low_price_brut = low_price * 20.0, close_price_brut = close_price * 20.0 WHERE instrument_id = 'bb7a06f0-e384-4d41-ab2b-6259f42c0526' AND date >= '1998-09-18' AND date <= '2017-09-07';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 20.0) WHERE instrument_id = 'bb7a06f0-e384-4d41-ab2b-6259f42c0526' AND date >= '1998-09-18' AND date <= '2017-09-07';

-- ONTBF (2009-04-30 -> 2013-11-28) : ratio x20.0  [717 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 20.0, high_price_brut = high_price * 20.0, low_price_brut = low_price * 20.0, close_price_brut = close_price * 20.0 WHERE instrument_id = '37f65957-d735-4d30-9259-a0057661a499' AND date >= '2009-04-30' AND date <= '2013-11-28';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 20.0) WHERE instrument_id = '37f65957-d735-4d30-9259-a0057661a499' AND date >= '2009-04-30' AND date <= '2013-11-28';

-- ONTBF (2013-11-29 -> 2018-08-28) : ratio x2.0  [1177 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 2.0, high_price_brut = high_price * 2.0, low_price_brut = low_price * 2.0, close_price_brut = close_price * 2.0 WHERE instrument_id = '37f65957-d735-4d30-9259-a0057661a499' AND date >= '2013-11-29' AND date <= '2018-08-28';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 2.0) WHERE instrument_id = '37f65957-d735-4d30-9259-a0057661a499' AND date >= '2013-11-29' AND date <= '2018-08-28';

-- PALC (1999-10-18 -> 2017-11-02) : ratio x2.0  [2686 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 2.0, high_price_brut = high_price * 2.0, low_price_brut = low_price * 2.0, close_price_brut = close_price * 2.0 WHERE instrument_id = '2cb3aeaf-e47e-48f0-ac1f-367a59d4fdf3' AND date >= '1999-10-18' AND date <= '2017-11-02';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 2.0) WHERE instrument_id = '2cb3aeaf-e47e-48f0-ac1f-367a59d4fdf3' AND date >= '1999-10-18' AND date <= '2017-11-02';

-- PRSC (1998-09-23 -> 2019-10-24) : ratio x63.9977  [956 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 63.9977, high_price_brut = high_price * 63.9977, low_price_brut = low_price * 63.9977, close_price_brut = close_price * 63.9977 WHERE instrument_id = 'b23e3c40-8987-4f72-bfed-e13810ca9a67' AND date >= '1998-09-23' AND date <= '2019-10-24';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 63.9977) WHERE instrument_id = 'b23e3c40-8987-4f72-bfed-e13810ca9a67' AND date >= '1998-09-23' AND date <= '2019-10-24';

-- SAFC (1998-09-23 -> 2017-10-11) : ratio x88.4521  [447 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 88.4521, high_price_brut = high_price * 88.4521, low_price_brut = low_price * 88.4521, close_price_brut = close_price * 88.4521 WHERE instrument_id = '2e917e79-74e0-41ad-b251-090e54daf531' AND date >= '1998-09-23' AND date <= '2017-10-11';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 88.4521) WHERE instrument_id = '2e917e79-74e0-41ad-b251-090e54daf531' AND date >= '1998-09-23' AND date <= '2017-10-11';

-- SAFC (2017-10-17 -> 2018-12-19) : ratio x35.3896  [60 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 35.3896, high_price_brut = high_price * 35.3896, low_price_brut = low_price * 35.3896, close_price_brut = close_price * 35.3896 WHERE instrument_id = '2e917e79-74e0-41ad-b251-090e54daf531' AND date >= '2017-10-17' AND date <= '2018-12-19';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 35.3896) WHERE instrument_id = '2e917e79-74e0-41ad-b251-090e54daf531' AND date >= '2017-10-17' AND date <= '2018-12-19';

-- SAFC (2019-01-08 -> 2026-04-23) : ratio x1.4151  [1192 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 1.4151, high_price_brut = high_price * 1.4151, low_price_brut = low_price * 1.4151, close_price_brut = close_price * 1.4151 WHERE instrument_id = '2e917e79-74e0-41ad-b251-090e54daf531' AND date >= '2019-01-08' AND date <= '2026-04-23';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 1.4151) WHERE instrument_id = '2e917e79-74e0-41ad-b251-090e54daf531' AND date >= '2019-01-08' AND date <= '2026-04-23';

-- SCRC (2016-12-29 -> 2017-11-30) : ratio x4.0  [229 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 4.0, high_price_brut = high_price * 4.0, low_price_brut = low_price * 4.0, close_price_brut = close_price * 4.0 WHERE instrument_id = '6065f6c8-ad0d-4128-838f-da2d6d646bee' AND date >= '2016-12-29' AND date <= '2017-11-30';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 4.0) WHERE instrument_id = '6065f6c8-ad0d-4128-838f-da2d6d646bee' AND date >= '2016-12-29' AND date <= '2017-11-30';

-- SDCC (1998-09-16 -> 2017-12-27) : ratio x10.0  [2178 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 10.0, high_price_brut = high_price * 10.0, low_price_brut = low_price * 10.0, close_price_brut = close_price * 10.0 WHERE instrument_id = 'dd48a739-9062-419a-bb4e-a1410ec8b8b1' AND date >= '1998-09-16' AND date <= '2017-12-27';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 10.0) WHERE instrument_id = 'dd48a739-9062-419a-bb4e-a1410ec8b8b1' AND date >= '1998-09-16' AND date <= '2017-12-27';

-- SDSC (2007-02-28 -> 2017-07-28) : ratio x50.0  [1514 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 50.0, high_price_brut = high_price * 50.0, low_price_brut = low_price * 50.0, close_price_brut = close_price * 50.0 WHERE instrument_id = 'd45eed14-5753-4df6-825e-13022d53a454' AND date >= '2007-02-28' AND date <= '2017-07-28';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 50.0) WHERE instrument_id = 'd45eed14-5753-4df6-825e-13022d53a454' AND date >= '2007-02-28' AND date <= '2017-07-28';

-- SEMC (1998-09-18 -> 2018-12-19) : ratio x40.0  [1074 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 40.0, high_price_brut = high_price * 40.0, low_price_brut = low_price * 40.0, close_price_brut = close_price * 40.0 WHERE instrument_id = 'be377e7f-2789-430b-b1b8-54940f8de624' AND date >= '1998-09-18' AND date <= '2018-12-19';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 40.0) WHERE instrument_id = 'be377e7f-2789-430b-b1b8-54940f8de624' AND date >= '1998-09-18' AND date <= '2018-12-19';

-- SGBC (1998-09-18 -> 2017-08-24) : ratio x10.0  [2572 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 10.0, high_price_brut = high_price * 10.0, low_price_brut = low_price * 10.0, close_price_brut = close_price * 10.0 WHERE instrument_id = 'a25124e1-ef48-4c12-8077-7761c89a1638' AND date >= '1998-09-18' AND date <= '2017-08-24';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 10.0) WHERE instrument_id = 'a25124e1-ef48-4c12-8077-7761c89a1638' AND date >= '1998-09-18' AND date <= '2017-08-24';

-- SHEC (1998-09-16 -> 2016-11-03) : ratio x50.0  [2489 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 50.0, high_price_brut = high_price * 50.0, low_price_brut = low_price * 50.0, close_price_brut = close_price * 50.0 WHERE instrument_id = 'ef1f11a1-ba78-4a07-8c73-be5f92767006' AND date >= '1998-09-16' AND date <= '2016-11-03';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 50.0) WHERE instrument_id = 'ef1f11a1-ba78-4a07-8c73-be5f92767006' AND date >= '1998-09-16' AND date <= '2016-11-03';

-- SIBC (2016-10-27 -> 2018-06-13) : ratio x10.0  [402 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 10.0, high_price_brut = high_price * 10.0, low_price_brut = low_price * 10.0, close_price_brut = close_price * 10.0 WHERE instrument_id = 'd7a9830d-fe01-4118-9e44-e08e142b58a5' AND date >= '2016-10-27' AND date <= '2018-06-13';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 10.0) WHERE instrument_id = 'd7a9830d-fe01-4118-9e44-e08e142b58a5' AND date >= '2016-10-27' AND date <= '2018-06-13';

-- SIBC (2018-06-15 -> 2024-11-13) : ratio x2.0  [1599 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 2.0, high_price_brut = high_price * 2.0, low_price_brut = low_price * 2.0, close_price_brut = close_price * 2.0 WHERE instrument_id = 'd7a9830d-fe01-4118-9e44-e08e142b58a5' AND date >= '2018-06-15' AND date <= '2024-11-13';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 2.0) WHERE instrument_id = 'd7a9830d-fe01-4118-9e44-e08e142b58a5' AND date >= '2018-06-15' AND date <= '2024-11-13';

-- SIVC (1999-04-19 -> 2017-12-20) : ratio x10.0  [2501 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 10.0, high_price_brut = high_price * 10.0, low_price_brut = low_price * 10.0, close_price_brut = close_price * 10.0 WHERE instrument_id = 'ea3fbdf1-be43-43b2-b133-3213120fe555' AND date >= '1999-04-19' AND date <= '2017-12-20';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 10.0) WHERE instrument_id = 'ea3fbdf1-be43-43b2-b133-3213120fe555' AND date >= '1999-04-19' AND date <= '2017-12-20';

-- SLBC (1998-09-23 -> 2014-12-29) : ratio x20.0  [873 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 20.0, high_price_brut = high_price * 20.0, low_price_brut = low_price * 20.0, close_price_brut = close_price * 20.0 WHERE instrument_id = '0149c32b-cfb6-4780-98bd-4e88ea76b896' AND date >= '1998-09-23' AND date <= '2014-12-29';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 20.0) WHERE instrument_id = '0149c32b-cfb6-4780-98bd-4e88ea76b896' AND date >= '1998-09-23' AND date <= '2014-12-29';

-- SLBC (2014-12-30 -> 2024-09-27) : ratio x10.0  [1392 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 10.0, high_price_brut = high_price * 10.0, low_price_brut = low_price * 10.0, close_price_brut = close_price * 10.0 WHERE instrument_id = '0149c32b-cfb6-4780-98bd-4e88ea76b896' AND date >= '2014-12-30' AND date <= '2024-09-27';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 10.0) WHERE instrument_id = '0149c32b-cfb6-4780-98bd-4e88ea76b896' AND date >= '2014-12-30' AND date <= '2024-09-27';

-- SMBC (1998-09-18 -> 2019-02-21) : ratio x4.0  [1975 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 4.0, high_price_brut = high_price * 4.0, low_price_brut = low_price * 4.0, close_price_brut = close_price * 4.0 WHERE instrument_id = '9f7860e3-72f3-4cd0-bd87-54637d35c7e8' AND date >= '1998-09-18' AND date <= '2019-02-21';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 4.0) WHERE instrument_id = '9f7860e3-72f3-4cd0-bd87-54637d35c7e8' AND date >= '1998-09-18' AND date <= '2019-02-21';

-- SNTS (1998-10-02 -> 2012-11-22) : ratio x10.0  [3072 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 10.0, high_price_brut = high_price * 10.0, low_price_brut = low_price * 10.0, close_price_brut = close_price * 10.0 WHERE instrument_id = 'dee23326-c0a1-4bc1-9815-6479c9feec68' AND date >= '1998-10-02' AND date <= '2012-11-22';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 10.0) WHERE instrument_id = 'dee23326-c0a1-4bc1-9815-6479c9feec68' AND date >= '1998-10-02' AND date <= '2012-11-22';

-- SOGC (1998-09-16 -> 2017-08-17) : ratio x10.0  [2656 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 10.0, high_price_brut = high_price * 10.0, low_price_brut = low_price * 10.0, close_price_brut = close_price * 10.0 WHERE instrument_id = '191ab18c-7b24-4115-9369-f013c21b71d2' AND date >= '1998-09-16' AND date <= '2017-08-17';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 10.0) WHERE instrument_id = '191ab18c-7b24-4115-9369-f013c21b71d2' AND date >= '1998-09-16' AND date <= '2017-08-17';

-- SPHC (1998-09-18 -> 2017-07-20) : ratio x5.0  [3156 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 5.0, high_price_brut = high_price * 5.0, low_price_brut = low_price * 5.0, close_price_brut = close_price * 5.0 WHERE instrument_id = '0ea36271-a8be-4a4f-aba0-95ccbacf164c' AND date >= '1998-09-18' AND date <= '2017-07-20';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 5.0) WHERE instrument_id = '0ea36271-a8be-4a4f-aba0-95ccbacf164c' AND date >= '1998-09-18' AND date <= '2017-07-20';

-- STAC (1998-10-07 -> 2017-10-24) : ratio x100.0  [498 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 100.0, high_price_brut = high_price * 100.0, low_price_brut = low_price * 100.0, close_price_brut = close_price * 100.0 WHERE instrument_id = '25d2f090-da59-4d5a-854b-08867e251c7c' AND date >= '1998-10-07' AND date <= '2017-10-24';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 100.0) WHERE instrument_id = '25d2f090-da59-4d5a-854b-08867e251c7c' AND date >= '1998-10-07' AND date <= '2017-10-24';

-- STBC (1998-09-21 -> 2018-07-25) : ratio x20.0  [2534 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 20.0, high_price_brut = high_price * 20.0, low_price_brut = low_price * 20.0, close_price_brut = close_price * 20.0 WHERE instrument_id = '938e6cfc-11b7-4476-942e-15b4c011f868' AND date >= '1998-09-21' AND date <= '2018-07-25';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 20.0) WHERE instrument_id = '938e6cfc-11b7-4476-942e-15b4c011f868' AND date >= '1998-09-21' AND date <= '2018-07-25';

-- TTLC (1998-09-16 -> 2015-07-24) : ratio x100.0  [1488 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 100.0, high_price_brut = high_price * 100.0, low_price_brut = low_price * 100.0, close_price_brut = close_price * 100.0 WHERE instrument_id = '8bad2525-9323-4e31-b12c-7a0735e95a2b' AND date >= '1998-09-16' AND date <= '2015-07-24';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 100.0) WHERE instrument_id = '8bad2525-9323-4e31-b12c-7a0735e95a2b' AND date >= '1998-09-16' AND date <= '2015-07-24';

-- TTLC (2015-07-27 -> 2018-02-09) : ratio x5.0  [632 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 5.0, high_price_brut = high_price * 5.0, low_price_brut = low_price * 5.0, close_price_brut = close_price * 5.0 WHERE instrument_id = '8bad2525-9323-4e31-b12c-7a0735e95a2b' AND date >= '2015-07-27' AND date <= '2018-02-09';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 5.0) WHERE instrument_id = '8bad2525-9323-4e31-b12c-7a0735e95a2b' AND date >= '2015-07-27' AND date <= '2018-02-09';

-- TTLS (2015-02-20 -> 2017-10-31) : ratio x10.0  [659 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 10.0, high_price_brut = high_price * 10.0, low_price_brut = low_price * 10.0, close_price_brut = close_price * 10.0 WHERE instrument_id = 'f9d97485-96fb-4573-9c0b-5c26dc7eaec9' AND date >= '2015-02-20' AND date <= '2017-10-31';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 10.0) WHERE instrument_id = 'f9d97485-96fb-4573-9c0b-5c26dc7eaec9' AND date >= '2015-02-20' AND date <= '2017-10-31';

-- UNXC (1998-09-18 -> 2015-04-29) : ratio x25.0  [770 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 25.0, high_price_brut = high_price * 25.0, low_price_brut = low_price * 25.0, close_price_brut = close_price * 25.0 WHERE instrument_id = '2fde1040-fbe9-4dfb-a158-42bccc413973' AND date >= '1998-09-18' AND date <= '2015-04-29';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 25.0) WHERE instrument_id = '2fde1040-fbe9-4dfb-a158-42bccc413973' AND date >= '1998-09-18' AND date <= '2015-04-29';

-- UNXC (2015-04-30 -> 2017-08-10) : ratio x5.0  [553 points Richbourse]
UPDATE public.daily_candles SET open_price_brut = open_price * 5.0, high_price_brut = high_price * 5.0, low_price_brut = low_price * 5.0, close_price_brut = close_price * 5.0 WHERE instrument_id = '2fde1040-fbe9-4dfb-a158-42bccc413973' AND date >= '2015-04-30' AND date <= '2017-08-10';
UPDATE public.daily_volume SET quantity = ROUND(quantity * 5.0) WHERE instrument_id = '2fde1040-fbe9-4dfb-a158-42bccc413973' AND date >= '2015-04-30' AND date <= '2017-08-10';


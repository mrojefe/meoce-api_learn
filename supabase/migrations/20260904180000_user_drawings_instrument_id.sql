-- user_drawings.symbol -> instrument_id (real FK, not a raw ticker string).
--
-- symbol had no integrity and the same ambiguity as E-20 (a symbol can exist on
-- two exchanges — SNTS did, until JF resolved the duplicate). Now that instruments
-- has no duplicate symbols, the backfill is unambiguous: every row joins to
-- exactly one instrument.

ALTER TABLE user_drawings
  ADD COLUMN instrument_id UUID REFERENCES instruments(id);

UPDATE user_drawings ud
   SET instrument_id = i.id
  FROM instruments i
 WHERE i.symbol = ud.symbol;

ALTER TABLE user_drawings ALTER COLUMN instrument_id SET NOT NULL;
ALTER TABLE user_drawings DROP COLUMN symbol;

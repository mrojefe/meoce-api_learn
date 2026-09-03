-- user_preferences had no DB-level defaults on its first-login columns —
-- the values were only known in Python (real API's PREFS_DEFAULTS, then
-- duplicated in meoce-api_learn's services/preferences.py). Two copies of
-- the same fact, one of which any future writer (a raw INSERT, a migration
-- script, another client) would silently miss. The database becomes the
-- single source of truth instead; Python drops its copy.

ALTER TABLE user_preferences
  ALTER COLUMN default_currency SET DEFAULT 'XOF',
  ALTER COLUMN default_language SET DEFAULT 'fr',
  ALTER COLUMN default_timeframe SET DEFAULT '1D',
  ALTER COLUMN default_chart_type SET DEFAULT 'candlestick';

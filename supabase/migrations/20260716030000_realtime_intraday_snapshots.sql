-- Active Supabase Realtime sur intraday_snapshots pour brancher la
-- watchlist en direct pendant la séance (comme TradingView) — jusqu'ici
-- aucune table n'était publiée pour Realtime, la watchlist ne se
-- rafraîchissait qu'au chargement de la page.
ALTER PUBLICATION supabase_realtime ADD TABLE intraday_snapshots;

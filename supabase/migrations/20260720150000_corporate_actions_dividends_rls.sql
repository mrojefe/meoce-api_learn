-- corporate_actions/dividends ont RLS activé mais AUCUNE policy depuis leur
-- création — accès anon bloqué par défaut (constaté : 500 "permission
-- denied for table corporate_actions" dès le premier appel public via
-- GET /instruments/{symbol}/profile). Référentiel public (comme
-- instruments/sectors/etc.), lecture ouverte à tous.
CREATE POLICY corporate_actions_read_all ON corporate_actions FOR SELECT USING (true);
CREATE POLICY dividends_read_all ON dividends FOR SELECT USING (true);

-- La policy RLS seule ne suffit pas : ces deux tables n'ont JAMAIS reçu le
-- GRANT SELECT de base pour anon/authenticated depuis leur création (constaté
-- via information_schema.role_table_grants — absent alors que présent sur
-- `instruments` et la quasi-totalité du référentiel public). Sans ce GRANT,
-- Postgres refuse l'accès avant même d'évaluer les policies RLS.
GRANT SELECT ON public.corporate_actions TO anon, authenticated;
GRANT SELECT ON public.dividends TO anon, authenticated;

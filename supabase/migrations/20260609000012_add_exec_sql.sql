CREATE OR REPLACE FUNCTION exec_sql(query text) RETURNS jsonb AS $$
DECLARE
  result jsonb;
BEGIN
  EXECUTE 'SELECT jsonb_agg(t) FROM (' || query || ') t' INTO result;
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

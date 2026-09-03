-- ============================================================
-- D128 — Finition des warnings Supabase Advisor (suite D127)
-- ============================================================
-- 1. ALTER ROLE anon + authenticated : ajouter "extensions" au search_path
--    (sinon le move de vector vers extensions casserait les queries qui
--    construisent un vector littéral, ex: '[1,2,3]'::vector)
-- 2. Move vector extension : public → extensions schema
-- 3. REVOKE EXECUTE ON rls_auto_enable FROM PUBLIC
--    (le REVOKE précédent ciblait anon/authenticated explicitement,
--     mais le grant est sur PUBLIC par défaut — il faut revoke PUBLIC)
-- ============================================================

-- 1) search_path : aligner anon + authenticated sur la config postgres
-- (postgres a déjà : "$user", public, extensions)
ALTER ROLE anon          SET search_path = "$user", public, extensions;
ALTER ROLE authenticated SET search_path = "$user", public, extensions;
ALTER ROLE service_role  SET search_path = "$user", public, extensions;

-- 2) Move vector extension to extensions schema
-- Les colonnes existantes (boc_embeddings.embedding) gardent leur type
-- (PostgreSQL track par OID, pas par nom). Les nouvelles requêtes pourront
-- toujours utiliser le type grâce au search_path ci-dessus.
ALTER EXTENSION vector SET SCHEMA extensions;

-- 3) Revoke EXECUTE on rls_auto_enable from PUBLIC
-- L'ACL actuelle est {=X/postgres, postgres=X/postgres} → PUBLIC a EXECUTE.
-- On retire PUBLIC. postgres garde EXECUTE (owner). Le trigger CREATE TABLE
-- événementiel continue de fonctionner (il tourne en tant que postgres).
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC;

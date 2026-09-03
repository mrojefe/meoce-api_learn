-- ============================================================
-- D127 — Sécurisation (réponse Supabase Advisor warnings)
-- ============================================================
-- 1. SET search_path = '' sur les 5 functions trigger (anti search_path injection)
--    → identifiers explicitement qualifiés dans les corps de fonctions
-- 2. Policy explicite "deny-all" sur audit_logs (silence INFO rls_enabled_no_policy
--    + intention claire : seul service_role lit les audits)
-- 3. REVOKE EXECUTE sur rls_auto_enable() des roles anon + authenticated
--    (fonction SECURITY DEFINER créée auto par Supabase, ne doit pas être
--    callable via API publique)
-- ============================================================

-- ----------------------------------------------------------------
-- 1) Functions : SET search_path = '' + qualifications explicites
-- ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = pg_catalog.now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.process_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF (TG_OP = 'UPDATE') THEN
    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data)
    VALUES (TG_TABLE_NAME, OLD.id::text, 'UPDATE', pg_catalog.to_jsonb(OLD), pg_catalog.to_jsonb(NEW));
    RETURN NEW;
  ELSIF (TG_OP = 'DELETE') THEN
    INSERT INTO public.audit_logs (table_name, record_id, action, old_data)
    VALUES (TG_TABLE_NAME, OLD.id::text, 'DELETE', pg_catalog.to_jsonb(OLD));
    RETURN OLD;
  ELSIF (TG_OP = 'INSERT') THEN
    INSERT INTO public.audit_logs (table_name, record_id, action, new_data)
    VALUES (TG_TABLE_NAME, NEW.id::text, 'INSERT', pg_catalog.to_jsonb(NEW));
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_proposal_vote_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.feature_proposals SET vote_count = vote_count + 1
      WHERE id = NEW.proposal_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.feature_proposals SET vote_count = vote_count - 1
      WHERE id = OLD.proposal_id;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_instrument_status_on_ca()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.type = 'delisting'
     AND NEW.status = 'effective'
     AND NEW.effective_date IS NOT NULL
     AND NEW.effective_date <= pg_catalog.current_date THEN
    UPDATE public.instruments SET status = 'delisted' WHERE id = NEW.instrument_id;
  ELSIF NEW.type = 'suspension'
        AND NEW.status = 'effective'
        AND NEW.effective_date IS NOT NULL
        AND NEW.effective_date <= pg_catalog.current_date THEN
    UPDATE public.instruments SET status = 'suspended' WHERE id = NEW.instrument_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_default_subscription()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.subscriptions (user_id, plan_code, status)
  VALUES (NEW.id, 'free', 'active');
  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------
-- 2) audit_logs : policy explicite "no public access"
-- ----------------------------------------------------------------
-- Intention : seul service_role (côté serveur) lit/écrit. Aucun user JWT n'y accède.
-- Cette policy rend l'intention EXPLICITE et silence l'advisor INFO.

CREATE POLICY no_public_access ON public.audit_logs
  FOR ALL
  USING (false)
  WITH CHECK (false);

-- ----------------------------------------------------------------
-- 3) rls_auto_enable : revoke EXECUTE des roles publics
-- ----------------------------------------------------------------
-- Fonction créée automatiquement par Supabase lors de l'activation
-- "Enable automatic RLS" à la création du projet. Utilisée par un trigger
-- événementiel sur CREATE TABLE → pas besoin d'être appelable via API REST.

REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM anon, authenticated;

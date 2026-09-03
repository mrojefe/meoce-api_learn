-- log_auth_event() : accepter l'IP et le user-agent du CLIENT explicitement.
--
-- Problème : la version initiale (20260725010000) déduisait le contexte réseau
-- de `request.headers`, c'est-à-dire des en-têtes vus par PostgREST. Or les
-- routes d'authentification vivent dans Next.js (Vercel) : quand elles appellent
-- PostgREST, l'IP observée est celle de la fonction serverless, PAS celle du
-- navigateur. On aurait donc journalisé l'IP de Vercel pour chaque connexion —
-- inutile pour tracer une attaque par force brute.
--
-- L'appelant transmet donc l'IP/user-agent réels (qu'il extrait lui-même de la
-- requête entrante). On garde le repli sur request.headers pour les appels
-- directs à PostgREST, où le contexte est fiable.
CREATE OR REPLACE FUNCTION public.log_auth_event(
  p_event_type text,
  p_user_id    uuid    DEFAULT NULL,
  p_identifier text    DEFAULT NULL,
  p_success    boolean DEFAULT true,
  p_reason     text    DEFAULT NULL,
  p_metadata   jsonb   DEFAULT NULL,
  p_client_ip  text    DEFAULT NULL,
  p_user_agent text    DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  ctx  jsonb := public.audit_request_context();
  v_ip inet;
  v_id uuid;
BEGIN
  -- IP fournie par l'appelant en priorité ; sinon celle vue par PostgREST.
  -- Une IP illisible ne doit jamais faire échouer la journalisation.
  BEGIN
    v_ip := coalesce(nullif(p_client_ip, ''), ctx ->> 'client_ip')::inet;
  EXCEPTION WHEN others THEN
    v_ip := NULL;
  END;

  INSERT INTO public.auth_events (event_type, user_id, identifier, success, reason,
                                  client_ip, user_agent, request_id, metadata)
  VALUES (p_event_type, p_user_id, p_identifier, p_success, p_reason,
          v_ip,
          pg_catalog.left(coalesce(nullif(p_user_agent, ''), ctx ->> 'user_agent', ''), 300),
          ctx ->> 'request_id',
          p_metadata)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- L'ancienne signature à 6 arguments deviendrait ambiguë avec celle-ci : on la
-- retire, aucun appelant ne l'utilise encore (fonction créée le jour même).
DROP FUNCTION IF EXISTS public.log_auth_event(text, uuid, text, boolean, text, jsonb);

REVOKE ALL ON FUNCTION public.log_auth_event(text, uuid, text, boolean, text, jsonb, text, text)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

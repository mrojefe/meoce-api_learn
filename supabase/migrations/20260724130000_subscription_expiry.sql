-- ============================================================================
-- CYCLE DE VIE DES ABONNEMENTS — expiration + rappels de renouvellement
--
-- Contexte Phase 1 : le Mobile Money n'a PAS de prélèvement automatique. Un
-- abonnement payé couvre 1 mois ; passé `current_period_end`, l'utilisateur doit
-- repayer. Il faut donc :
--   1. le PRÉVENIR avant l'échéance (J-3, J-1) — sinon il perd ses droits sans
--      comprendre, et c'est du churn évitable ;
--   2. le REBASCULER en 'free' à l'échéance, de façon FIABLE et TRAÇABLE.
--
-- Tout est journalisé : chaque rappel envoyé et chaque expiration laissent une
-- trace (on stocke tout, aucune décision silencieuse sur un compte payant).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Journal des rappels — évite d'envoyer 10 fois le même rappel
--    (le cron tourne toutes les heures : sans ce garde-fou, spam garanti).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subscription_reminders (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  subscription_id UUID        REFERENCES public.subscriptions(id) ON DELETE SET NULL,
  plan_code       TEXT,
  -- 'j3' | 'j1' | 'expired' : nature du message envoyé.
  kind            TEXT        NOT NULL,
  channel         TEXT        NOT NULL DEFAULT 'email',
  -- Échéance visée : rend la clé d'unicité stable même si l'abonnement est
  -- renouvelé plus tard (nouvelle échéance = nouveau cycle de rappels).
  period_end      TIMESTAMPTZ NOT NULL,
  sent_ok         BOOLEAN     NOT NULL DEFAULT true,
  error_text      TEXT,
  payload         JSONB,                       -- on stocke tout (contenu, destinataire…)
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Un seul rappel de chaque type par échéance et par utilisateur.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_sub_reminder_once
  ON public.subscription_reminders(user_id, kind, period_end);

CREATE INDEX IF NOT EXISTS idx_sub_reminders_user ON public.subscription_reminders(user_id);

ALTER TABLE public.subscription_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sub_reminders_select_own ON public.subscription_reminders;
CREATE POLICY sub_reminders_select_own ON public.subscription_reminders
  FOR SELECT USING (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- 2) Expiration ATOMIQUE des abonnements échus
--
--    Repasse en 'free' tout abonnement payant dont la période est terminée.
--    • `status` reste 'active' avec plan_code='free' (et non 'expired') : la
--      contrainte uniq_user_active_sub veut UNE ligne active par user, et un
--      utilisateur sans ligne active casserait les vérifications de quota
--      (le trigger d'inscription pose bien 'free'/'active' — on reste cohérent).
--    • `current_period_end = NULL` : le plan gratuit n'expire pas.
--    • Trace complète conservée (ancien plan, ancienne échéance) dans le retour
--      ET dans l'audit (trigger d'audit déjà posé sur `subscriptions`).
--
--    Idempotente : une fois basculée, la ligne ne matche plus le WHERE.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_due_subscriptions()
RETURNS TABLE (
  user_id          UUID,
  subscription_id  UUID,
  previous_plan    TEXT,
  previous_end     TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT s.id, s.user_id, s.plan_code, s.current_period_end
      FROM public.subscriptions s
     WHERE s.plan_code <> 'free'
       AND s.status IN ('active', 'trial')
       AND s.current_period_end IS NOT NULL
       AND s.current_period_end <= now()
     FOR UPDATE
  ),
  updated AS (
    UPDATE public.subscriptions s
       SET plan_code            = 'free',
           status               = 'active',
           current_period_start = now(),
           current_period_end   = NULL,
           cancellation_reason  = COALESCE(s.cancellation_reason,
                                           'Période payée terminée (non renouvelé)')
      FROM due
     WHERE s.id = due.id
     RETURNING s.id, s.user_id, due.plan_code AS previous_plan, due.current_period_end AS previous_end
  )
  SELECT u.user_id, u.id, u.previous_plan, u.previous_end FROM updated u;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_due_subscriptions() FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3) Abonnements arrivant à échéance — pour les rappels J-3 / J-1.
--    Renvoie aussi l'email/téléphone : le cron n'a alors qu'UNE requête à faire.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.subscriptions_due_soon(p_days INT)
RETURNS TABLE (
  user_id     UUID,
  subscription_id UUID,
  plan_code   TEXT,
  period_end  TIMESTAMPTZ,
  email       TEXT,
  phone       TEXT,
  username    TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.user_id, s.id, s.plan_code, s.current_period_end,
         u.email, u.phone, u.username
    FROM public.subscriptions s
    JOIN public.users u ON u.id = s.user_id
   WHERE s.plan_code <> 'free'
     AND s.status IN ('active', 'trial')
     AND s.current_period_end IS NOT NULL
     -- Fenêtre d'un jour : échéance dans exactement p_days jours.
     AND s.current_period_end >  now() + ((p_days - 1) || ' day')::interval
     AND s.current_period_end <= now() + (p_days || ' day')::interval;
$$;

REVOKE ALL ON FUNCTION public.subscriptions_due_soon(INT) FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- PAIEMENTS — GeniusPay (Phase 1 : Mobile Money ponctuel)
--
-- Architecture retenue (vérifié : aucune table `payments` en base avant celle-ci) :
--
--  1. `payments`        = l'INTENTION de paiement (une par tentative), portant la
--                         clé d'idempotence. C'est l'agrégat.
--  2. `payment_events`  = LEDGER IMMUABLE, append-only : chaque changement d'état
--                         est une NOUVELLE LIGNE, jamais un UPDATE. On ne perd
--                         jamais l'historique (audit, litige, régulateur).
--                         Le statut courant se DÉRIVE de la timeline complète —
--                         donc des webhooks arrivant dans le désordre ne peuvent
--                         pas faire régresser un paiement déjà capturé.
--
-- Pourquoi (leçons système de paiement) :
--   • IDEMPOTENCE : un client qui renvoie sa requête (Wi-Fi, timeout, double clic)
--     ne doit JAMAIS être débité deux fois → `idempotency_key` UNIQUE par user :
--     même clé = on renvoie le résultat déjà stocké, on ne rappelle pas GeniusPay.
--   • ÉVÉNEMENTS ASYNCHRONES : un paiement vit dans le temps (initié → autorisé →
--     capturé → remboursé → contesté 3 mois plus tard). Un seul champ `status`
--     écrasé détruit la piste d'audit.
--   • DÉDUPLICATION D'ÉVÉNEMENTS : `provider_event_id` UNIQUE → un même événement
--     rejoué par le prestataire n'est ajouté qu'une fois.
--   • ON STOCKE TOUT (pas de contrainte de volume) : payload brut intégral,
--     en-têtes HTTP, IP source, réponse brute de création. Rien n'est jeté.
--
-- Le montant et le plan sont écrits par le SERVEUR (jamais par le client).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) payments — l'intention (agrégat)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payments (
  id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID          NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  -- Clé d'idempotence fournie par le client (UUID) : REJOUER la même requête
  -- renvoie le même paiement au lieu d'en créer/facturer un second.
  idempotency_key TEXT         NOT NULL,

  -- Référence GeniusPay (MTX-... en prod, SANDBOX_... en sandbox) = clé de
  -- réconciliation. NULL tant que l'appel au prestataire n'a pas abouti
  -- (cas « écrit avant l'appel » : on trace l'intention AVANT l'effet de bord).
  reference      TEXT          UNIQUE,
  provider       TEXT          NOT NULL DEFAULT 'geniuspay',
  environment    TEXT,                                  -- sandbox | live (tel que renvoyé)

  plan_code      TEXT          NOT NULL REFERENCES public.subscription_plans(code),
  amount_xof     NUMERIC(10,2) NOT NULL,
  currency       TEXT          NOT NULL DEFAULT 'XOF',

  -- Statut COURANT : cache dérivé du ledger (payment_events), pour les requêtes
  -- simples. La VÉRITÉ reste la timeline d'événements.
  status         TEXT          NOT NULL DEFAULT 'created'
                               CHECK (status IN ('created','pending','processing','completed','failed','expired','refunded','disputed')),
  payment_method TEXT,                                  -- wave, orange_money, mtn_money, card…
  checkout_url   TEXT,
  expires_at     TIMESTAMPTZ,

  -- Verrou d'application de l'abonnement (crédité une seule fois).
  applied        BOOLEAN       NOT NULL DEFAULT false,
  applied_at     TIMESTAMPTZ,

  -- ON STOCKE TOUT : réponse brute de création + contexte de la requête.
  create_request  JSONB,                                -- ce qu'on a envoyé
  create_response JSONB,                                -- ce que le prestataire a répondu (brut)
  client_ip       TEXT,
  user_agent      TEXT,

  created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Idempotence réelle : une clé ne vaut que pour SON utilisateur (empêche
-- qu'un tiers devine/réutilise la clé d'un autre).
CREATE UNIQUE INDEX IF NOT EXISTS uniq_payments_user_idem
  ON public.payments(user_id, idempotency_key);

CREATE INDEX IF NOT EXISTS idx_payments_user   ON public.payments(user_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments(status);
-- Réconciliation : paiements réussis pas encore crédités.
CREATE INDEX IF NOT EXISTS idx_payments_pending_apply
  ON public.payments(status) WHERE applied = false;

DROP TRIGGER IF EXISTS trg_payments_updated_at ON public.payments;
CREATE TRIGGER trg_payments_updated_at
  BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trg_audit_payments ON public.payments;
CREATE TRIGGER trg_audit_payments
  AFTER INSERT OR UPDATE OR DELETE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION process_audit_log();

-- ----------------------------------------------------------------------------
-- 2) payment_events — LEDGER IMMUABLE (append-only)
--    Une ligne par événement. JAMAIS d'UPDATE, JAMAIS de DELETE (voir triggers
--    de protection plus bas). Le statut courant se dérive de ces lignes.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_events (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id   UUID        REFERENCES public.payments(id) ON DELETE CASCADE,
  -- Conservée en clair : un événement peut arriver AVANT qu'on ait rattaché
  -- le paiement (ou pour une référence inconnue) — on ne jette rien.
  reference    TEXT,

  -- Type d'événement métier : intent_created, payment_pending, payment_completed,
  -- payment_failed, payment_expired, refunded, disputed, verification_failed…
  event_type   TEXT        NOT NULL,
  -- Statut porté par cet événement (si applicable) — sert à la dérivation.
  status       TEXT,

  -- Identifiant d'événement CHEZ LE PRESTATAIRE : déduplication (un même
  -- événement rejoué n'est inséré qu'une fois — cf. index unique plus bas).
  provider_event_id TEXT,

  -- Origine : 'server' (nous), 'webhook' (prestataire), 'reconciliation' (job),
  -- 'admin' (intervention humaine).
  source       TEXT        NOT NULL DEFAULT 'webhook',

  amount_xof   NUMERIC(10,2),

  -- ON STOCKE TOUT — brut, intégral, jamais tronqué.
  raw_payload  JSONB,                                   -- corps reçu tel quel
  raw_headers  JSONB,                                   -- en-têtes HTTP du webhook
  client_ip    TEXT,
  note         TEXT,                                    -- contexte lisible (debug/audit)

  -- Horodatage annoncé par le prestataire (peut différer de notre réception :
  -- c'est justement ce qui crée les arrivées dans le désordre).
  provider_timestamp TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_events_payment ON public.payment_events(payment_id, created_at);
CREATE INDEX IF NOT EXISTS idx_payment_events_ref     ON public.payment_events(reference);
CREATE INDEX IF NOT EXISTS idx_payment_events_type    ON public.payment_events(event_type);

-- Déduplication des événements du prestataire (NULL autorisés = nos propres
-- événements internes, qui n'ont pas d'id externe).
CREATE UNIQUE INDEX IF NOT EXISTS uniq_payment_events_provider_event
  ON public.payment_events(provider_event_id)
  WHERE provider_event_id IS NOT NULL;

-- ── Immuabilité RÉELLE, garantie EN BASE (pas seulement par convention) ──
CREATE OR REPLACE FUNCTION public.payment_events_no_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'payment_events est un ledger immuable : % interdit', TG_OP;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_events_immutable ON public.payment_events;
CREATE TRIGGER trg_payment_events_immutable
  BEFORE UPDATE OR DELETE ON public.payment_events
  FOR EACH ROW EXECUTE FUNCTION public.payment_events_no_mutation();

-- ----------------------------------------------------------------------------
-- 3) Dérivation du statut courant depuis la TIMELINE (anti désordre)
--    Priorité par gravité/finalité, pas par ordre d'arrivée :
--    disputed > refunded > completed > failed > expired > processing > pending > created
--    Ainsi un 'pending' qui arrive APRÈS un 'completed' ne fait pas régresser.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.derive_payment_status(p_payment_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT e.status
       FROM public.payment_events e
      WHERE e.payment_id = p_payment_id
        AND e.status IS NOT NULL
      ORDER BY CASE e.status
                 WHEN 'disputed'   THEN 8
                 WHEN 'refunded'   THEN 7
                 WHEN 'completed'  THEN 6
                 WHEN 'failed'     THEN 5
                 WHEN 'expired'    THEN 4
                 WHEN 'processing' THEN 3
                 WHEN 'pending'    THEN 2
                 WHEN 'created'    THEN 1
                 ELSE 0
               END DESC,
               e.created_at DESC
      LIMIT 1),
    'created');
$$;

-- Le cache `payments.status` suit automatiquement le ledger à chaque insertion.
CREATE OR REPLACE FUNCTION public.sync_payment_status_from_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.payment_id IS NOT NULL THEN
    UPDATE public.payments p
       SET status = public.derive_payment_status(NEW.payment_id)
     WHERE p.id = NEW.payment_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_events_sync_status ON public.payment_events;
CREATE TRIGGER trg_payment_events_sync_status
  AFTER INSERT ON public.payment_events
  FOR EACH ROW EXECUTE FUNCTION public.sync_payment_status_from_ledger();

-- ----------------------------------------------------------------------------
-- 4) CRÉDIT DE L'ABONNEMENT — ATOMIQUE (ACID)
--
-- Angle mort classique : créditer l'abonnement puis marquer le paiement comme
-- appliqué en DEUX requêtes séparées. Si le process meurt entre les deux
-- (coupure, timeout, crash), l'abonnement est crédité mais `applied` reste
-- false → le webhook suivant CRÉDITE UNE SECONDE FOIS (mois offert en double).
--
-- Une fonction plpgsql s'exécute dans UNE seule transaction : soit l'abonnement
-- ET le marqueur ET l'événement passent, soit RIEN ne passe. Plus d'état bâtard.
--
-- Le verrou d'idempotence est pris EN BASE (UPDATE ... WHERE applied = false
-- avec vérification du nombre de lignes touchées) : deux webhooks simultanés ne
-- peuvent pas créditer deux fois — le second voit 0 ligne et sort.
--
-- Renouvellement anticipé : on prolonge depuis la fin de période en cours si
-- elle est dans le futur → l'utilisateur ne perd jamais ses jours déjà payés.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_payment_to_subscription(
  p_payment_id UUID,
  p_months     INT DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pay           public.payments%ROWTYPE;
  v_sub_id        UUID;
  v_period_end    TIMESTAMPTZ;
  v_base          TIMESTAMPTZ;
  v_now           TIMESTAMPTZ := now();
  v_marked        INT;
  v_current_plan  TEXT;
  v_current_price NUMERIC := 0;
  v_new_price     NUMERIC := 0;
BEGIN
  -- Verrou de ligne : sérialise deux webhooks concurrents sur le même paiement.
  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'payment_not_found');
  END IF;

  -- Idempotence : déjà crédité → on ne refait rien (et ce n'est pas une erreur).
  IF v_pay.applied THEN
    RETURN jsonb_build_object('ok', true, 'already_applied', true);
  END IF;

  -- Abonnement actif courant (tout user en a un : trigger 'free' à l'inscription).
  SELECT id, current_period_end, plan_code INTO v_sub_id, v_base, v_current_plan
    FROM public.subscriptions
   WHERE user_id = v_pay.user_id
     AND status IN ('trial', 'active')
   ORDER BY started_at DESC
   LIMIT 1
   FOR UPDATE;

  -- ── Protection ANTI-DÉCLASSEMENT ────────────────────────────────────────────
  -- Un utilisateur déjà Pro qui paie un plan MOINS cher (clic sur « Plus », ou
  -- lien de paiement rejoué) perdrait ses droits Pro pour un mois entier, sans
  -- l'avoir voulu. On refuse de dégrader : le paiement N'EST PAS appliqué, il
  -- reste `applied = false` (donc rattrapable/remboursable), et l'événement est
  -- tracé pour que le support voie exactement ce qui s'est passé.
  SELECT COALESCE(monthly_price_xof, 0) INTO v_current_price
    FROM public.subscription_plans WHERE code = v_current_plan;
  SELECT COALESCE(monthly_price_xof, 0) INTO v_new_price
    FROM public.subscription_plans WHERE code = v_pay.plan_code;

  IF v_current_plan IS DISTINCT FROM v_pay.plan_code
     AND v_current_price > v_new_price
     AND (v_base IS NOT NULL AND v_base > v_now)  -- son plan supérieur court encore
  THEN
    INSERT INTO public.payment_events (
      payment_id, reference, event_type, status, source, amount_xof, note
    ) VALUES (
      p_payment_id, v_pay.reference, 'downgrade_blocked', NULL, 'server',
      v_pay.amount_xof,
      format('Déclassement refusé : plan actif %s (%s XOF) > plan payé %s (%s XOF), actif jusqu''au %s. Paiement NON appliqué — à traiter par le support.',
             v_current_plan, v_current_price, v_pay.plan_code, v_new_price, v_base)
    );
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'downgrade_blocked',
      'current_plan', v_current_plan,
      'paid_plan', v_pay.plan_code
    );
  END IF;

  IF v_base IS NULL OR v_base <= v_now THEN
    v_base := v_now;
  END IF;
  v_period_end := v_base + (p_months || ' month')::interval;

  IF v_sub_id IS NOT NULL THEN
    UPDATE public.subscriptions
       SET plan_code                = v_pay.plan_code,
           status                   = 'active',
           current_period_start     = v_now,
           current_period_end       = v_period_end,
           cancelled_at             = NULL,
           cancellation_reason      = NULL,
           payment_provider         = v_pay.provider,
           external_subscription_id = v_pay.reference
     WHERE id = v_sub_id;
  ELSE
    INSERT INTO public.subscriptions (
      user_id, plan_code, status, current_period_start, current_period_end,
      payment_provider, external_subscription_id
    ) VALUES (
      v_pay.user_id, v_pay.plan_code, 'active', v_now, v_period_end,
      v_pay.provider, v_pay.reference
    );
  END IF;

  -- Marqueur d'application — gardé par `applied = false` (double sécurité).
  UPDATE public.payments
     SET applied = true, applied_at = v_now
   WHERE id = p_payment_id AND applied = false;
  GET DIAGNOSTICS v_marked = ROW_COUNT;

  IF v_marked = 0 THEN
    -- Un concurrent a gagné la course : on annule TOUT (atomicité).
    RAISE EXCEPTION 'concurrent_apply_detected';
  END IF;

  -- Trace ledger du crédit effectif (même transaction).
  INSERT INTO public.payment_events (
    payment_id, reference, event_type, status, source, amount_xof, note
  ) VALUES (
    p_payment_id, v_pay.reference, 'subscription_credited', 'completed', 'server',
    v_pay.amount_xof,
    format('Abonnement %s crédité jusqu''au %s', v_pay.plan_code, v_period_end)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'plan_code', v_pay.plan_code,
    'current_period_end', v_period_end
  );
END;
$$;

REVOKE ALL ON FUNCTION public.apply_payment_to_subscription(UUID, INT) FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 5) RLS — lecture de SES propres paiements/événements. Aucune policy d'écriture :
--    seules les routes serveur (service_role, qui bypasse la RLS) écrivent.
--    Un client qui pourrait écrire s'auto-créditerait un abonnement.
-- ----------------------------------------------------------------------------
ALTER TABLE public.payments       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payments_select_own ON public.payments;
CREATE POLICY payments_select_own ON public.payments
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS payment_events_select_own ON public.payment_events;
CREATE POLICY payment_events_select_own ON public.payment_events
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.payments p
             WHERE p.id = payment_events.payment_id
               AND p.user_id = auth.uid())
  );

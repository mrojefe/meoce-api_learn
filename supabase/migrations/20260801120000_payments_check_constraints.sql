-- CHECK constraints manquantes sur le flux de paiement (tâche #63, 2026-08-01).
--
-- Constat : payments.provider, payments.environment, payment_events.status et
-- payment_events.event_type n'avaient AUCUNE contrainte CHECK/FK, alors que
-- payments.status en avait déjà une (migration 20260724110000_payments_geniuspay.sql) :
--   CHECK (status IN ('created','pending','processing','completed','failed',
--                      'expired','refunded','disputed'))
--
-- GeniusPay est en PRODUCTION RÉELLE (paiements réels). Avant d'ajouter quoi que
-- ce soit, vérifié :
--   1. Les valeurs RÉELLEMENT en base (docker exec ... psql -c "SELECT DISTINCT ...")
--      → provider: 'geniuspay' uniquement (13 lignes)
--      → environment: 'sandbox', 'live', NULL (1 ligne NULL — paiement échoué tôt,
--        avant que le provider ne renvoie l'environnement ; PAS de chaîne vide)
--      → payment_events.status: 'created','pending','completed','failed','expired'
--        + NULL (8 lignes NULL — chemins volontaires : webhook_no_reference,
--        webhook_unknown_reference, verification_failed, verified_by_signature
--        en test sandbox ; PAS de chaîne vide malgré l'apparence dans un premier
--        SELECT — vérifié avec count(*) FILTER (WHERE status = '') = 0)
--   2. Le code applicatif RÉEL du flux (PAS dans ce repo meoce-api — le webhook/
--      checkout/reconcile GeniusPay vit dans meoce-frontend :
--      src/app/api/payments/{webhook,checkout,reconcile}/route.ts +
--      src/lib/payments/geniuspay.ts) :
--      - normalizeStatus() / statusFromEvent() ne produisent jamais que
--        NULL ou l'un des 8 statuts déjà couverts par la contrainte payments.status.
--      - environment vient de `d.environment ?? null` (réponse GeniusPay),
--        documenté "sandbox | live" dans geniuspay.ts.
--      - event_type est en partie un littéral interne connu (webhook_no_reference,
--        webhook_unknown_reference, verified_by_signature, verification_failed,
--        verification_skipped_sandbox, webhook_received, amount_mismatch,
--        intent_superseded, intent_created, intent_failed, checkout_created,
--        reconciliation_check, reconciliation_unknown_reference, intent_abandoned,
--        subscription_credited, downgrade_blocked — ces deux derniers posés par
--        la fonction SQL apply_payment_to_subscription()), et en partie une
--        chaîne VENANT DU PRESTATAIRE (en-tête X-Webhook-Event, ex. observé en
--        base : 'payment.success') → PAS un ensemble fermé, GeniusPay peut
--        introduire de nouveaux noms d'événement à tout moment.
--      - Important : dans webhook/route.ts, `logEvent()` avale toute erreur
--        d'insertion (sauf 23505/doublon) SANS jamais interrompre le crédit du
--        paiement (commentaire explicite dans le code : "on ne jette jamais
--        rien"). Une contrainte trop stricte sur event_type ne peut donc PAS
--        bloquer un paiement réel — au pire elle ferait perdre une ligne de
--        traçabilité, jamais un crédit d'abonnement.
--
-- Décisions :
--   - provider      : IN ('geniuspay') — seule valeur jamais vue, alignée sur le
--     défaut de colonne. Si un 2e PSP arrive un jour, migration à part.
--   - environment   : NULL autorisé (paiement créé avant retour du provider) +
--     'sandbox'/'live'.
--   - payment_events.status : NULL autorisé (chemins d'échec sans statut connu)
--     + les 8 valeurs déjà utilisées par payments.status (même vocabulaire,
--     cohérence intentionnelle avec la fonction derive_payment_status()).
--   - payment_events.event_type : PAS d'énumération fermée (vocabulaire
--     partiellement contrôlé par GeniusPay, cf. ci-dessus) — on se contente de
--     rejeter NULL/vide et les caractères non attendus (garde-fou anti-garbage/
--     injection, pas un contrôle métier).

ALTER TABLE public.payments
  ADD CONSTRAINT payments_provider_check
  CHECK (provider IN ('geniuspay'));

ALTER TABLE public.payments
  ADD CONSTRAINT payments_environment_check
  CHECK (environment IS NULL OR environment IN ('sandbox', 'live'));

ALTER TABLE public.payment_events
  ADD CONSTRAINT payment_events_status_check
  CHECK (status IS NULL OR status IN (
    'created', 'pending', 'processing', 'completed',
    'failed', 'expired', 'refunded', 'disputed'
  ));

ALTER TABLE public.payment_events
  ADD CONSTRAINT payment_events_event_type_check
  CHECK (event_type <> '' AND event_type ~ '^[a-z0-9_.]+$');

COMMENT ON CONSTRAINT payments_provider_check ON public.payments IS
  'Seul GeniusPay existe à ce jour. Étendre la liste si un 2e PSP est intégré.';
COMMENT ON CONSTRAINT payments_environment_check ON public.payments IS
  'sandbox | live, tel que renvoyé par GeniusPay. NULL toléré (échec avant réponse provider).';
COMMENT ON CONSTRAINT payment_events_status_check ON public.payment_events IS
  'Même vocabulaire que payments.status (migration 20260724110000). NULL toléré (chemins sans statut prestataire connu).';
COMMENT ON CONSTRAINT payment_events_event_type_check ON public.payment_events IS
  'Garde-fou format seulement (minuscules/chiffres/underscore/point) — event_type inclut des noms d''événement fournis par GeniusPay (ex. X-Webhook-Event), volontairement PAS énuméré en dur.';

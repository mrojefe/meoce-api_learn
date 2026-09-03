-- ============================================================================
-- user_alerts.channel — colonne réelle (au lieu du canal planqué dans payload)
--
-- Audit plans custom 2026-07-22 : max_alerts_email_active / max_alerts_whatsapp_active
-- existent dans `features` mais n'ont JAMAIS été vérifiés nulle part — n'importe
-- qui pouvait créer un nombre illimité d'alertes actives, gratuit ou pas. Pour
-- pouvoir compter "combien d'alertes actives par canal", il faut un canal
-- interrogeable en SQL — aujourd'hui il n'existe que dans `payload.notificationChannel`
-- (JSON, valeurs frontend 'gmail'|'whatsapp'|'both').
--
-- 'gmail' (nom frontend historique) -> 'email' (nom de la clé d'entitlement).
-- 'both' compte simultanément dans les deux limites (email ET whatsapp).
-- ============================================================================

ALTER TABLE public.user_alerts
  ADD COLUMN IF NOT EXISTS channel TEXT NOT NULL DEFAULT 'email'
    CHECK (channel IN ('email', 'whatsapp', 'both'));

-- Backfill depuis le payload existant (idempotent — ne touche que les lignes
-- où le payload contredit le défaut posé par ADD COLUMN).
UPDATE public.user_alerts
   SET channel = CASE payload->>'notificationChannel'
                   WHEN 'gmail' THEN 'email'
                   WHEN 'whatsapp' THEN 'whatsapp'
                   WHEN 'both' THEN 'both'
                   ELSE 'email'
                 END
 WHERE payload ? 'notificationChannel';

-- Index de comptage "alertes actives par canal" (même motif que idx_user_alerts_active_by_symbol).
CREATE INDEX IF NOT EXISTS idx_user_alerts_active_by_user_channel
    ON public.user_alerts (user_id, channel)
    WHERE status = 'active' AND deleted_at IS NULL;

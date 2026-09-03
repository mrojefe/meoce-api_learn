-- 20260712200000_create_user_alerts.sql
-- Trace la table user_alerts qui existait déjà en base mais n'était couverte
-- par AUCUNE migration (dérive Git : impossible de reconstruire un environnement
-- neuf). Migration 100 % IDEMPOTENTE et NON destructive : elle reflète le schéma
-- live à l'identique (colonnes, index, FK, RLS) via IF NOT EXISTS / guards, donc
-- son application sur la base actuelle est un no-op et sur une base neuve elle
-- recrée exactement la table.
--
-- Rôle : persistance compte des alertes de prix (source de vérité serveur).
--   - Écrite par le frontend via PUT /api/alerts (service_role, filtre user_id JWT).
--   - Lue par le worker Airflow dag_check_alerts (condition/trigger_value/payload)
--     pour déclencher email (Brevo) + WhatsApp et marquer status='triggered'.

CREATE TABLE IF NOT EXISTS public.user_alerts (
    id            uuid        NOT NULL,
    user_id       uuid        NOT NULL,
    symbol        text        NOT NULL,
    status        text        NOT NULL DEFAULT 'active',
    condition     text        NOT NULL,
    trigger_value numeric     NOT NULL,
    payload       jsonb       NOT NULL,
    deleted_at    timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_alerts_pkey PRIMARY KEY (id)
);

-- FK vers users(id) (le miroir de user_profiles) — ON DELETE CASCADE.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'user_alerts_user_id_fkey'
    ) THEN
        ALTER TABLE public.user_alerts
            ADD CONSTRAINT user_alerts_user_id_fkey
            FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Index de filtrage worker : « alertes actives par symbole » sans scanner le jsonb.
CREATE INDEX IF NOT EXISTS idx_user_alerts_active_by_symbol
    ON public.user_alerts (symbol)
    WHERE status = 'active' AND deleted_at IS NULL;

-- Index d'isolation/lecture par utilisateur.
CREATE INDEX IF NOT EXISTS idx_user_alerts_user_symbol
    ON public.user_alerts (user_id, symbol);

-- RLS : défense en profondeur (l'app passe en service_role qui bypasse, mais on
-- garde la policy own_all pour un éventuel accès au JWT du user). auth.uid() est
-- NULL avec le JWT custom → policy dormante mais non nuisible.
ALTER TABLE public.user_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS own_all ON public.user_alerts;
CREATE POLICY own_all ON public.user_alerts
    USING (auth.uid() = user_id);

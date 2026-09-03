-- ⚠️ RENOMMÉE le 2026-07-25 : ce fichier portait la version 20260717040000,
-- DÉJÀ utilisée par `news_items_content`. Une seule des deux pouvait être
-- enregistrée dans schema_migrations (c'est news_items_content qui l'a été).
-- Conséquence : le correctif ci-dessous, pourtant bien appliqué en production,
-- aurait été SAUTÉ lors d'une reconstruction de la base — le bug des favoris de
-- graphe serait réapparu silencieusement. Version décalée à 20260717045000.
-- Contenu inchangé, et idempotent (DROP IF EXISTS puis recréation).

-- Corrige un 500 en production sur POST /api/user/chart-templates (favoris/autosave de
-- graphe JAMAIS enregistrés).
--
-- Cause racine (confirmée en base) : la contrainte `chart_templates_chart_type_check`
-- n'autorise que ('candlestick','bar','line','area','heikin_ashi','renko'). Or le front
-- (type TS `ChartType`, src/types/market.ts) écrit des ids ABSENTS de cette liste :
-- 'hollowCandle', 'volCandles', 'stepline', 'baseline', 'ha', 'histogram', 'equivolume'.
-- Dès que l'utilisateur est dans un de ces modes (ex. bougie de volume = 'volCandles'),
-- l'INSERT viole le CHECK → 23514 → la route renvoie 500 → rien n'est persisté (le layout
-- ET les indicateurs/outils favoris qui voyagent dans le même enregistrement).
-- À l'inverse 'heikin_ashi' et 'renko' autorisés en base n'existent PAS côté front (le front
-- utilise 'ha', et 'renko' n'est pas implémenté).
--
-- Fix : aligner le CHECK sur l'énumération réelle `ChartType`. On garde 'heikin_ashi' et
-- 'renko' par sécurité (compat descendante, aucune ligne ne les utilise mais no-op).
-- Aucune donnée touchée (DDL de contrainte uniquement). Idempotent (DROP IF EXISTS + ADD).

ALTER TABLE public.chart_templates
  DROP CONSTRAINT IF EXISTS chart_templates_chart_type_check;

ALTER TABLE public.chart_templates
  ADD CONSTRAINT chart_templates_chart_type_check
  CHECK (chart_type IN (
    'candlestick', 'bar', 'line', 'area', 'histogram', 'equivolume',
    'hollowCandle', 'baseline', 'stepline', 'ha', 'volCandles',
    'heikin_ashi', 'renko'  -- compat descendante (non émis par le front actuel)
  ));

-- Élargit la contrainte CHECK de user_preferences.default_chart_type.
--
-- CONTEXTE (audit persistance 2026-07-19) : l'application propose 9 types de graphe
-- (bar, candlestick, hollowCandle, volCandles, line, stepline, area, baseline, ha) mais
-- la contrainte n'en autorisait que 6 ('candlestick','bar','line','area','heikin_ashi','renko').
-- Les 5 types PRO (ha, hollowCandle, volCandles, stepline, baseline) étaient REJETÉS à
-- l'écriture, et l'erreur était avalée en silence côté client → le type par défaut d'un
-- compte PRO n'était jamais enregistré. La table sœur chart_templates.chart_type accepte
-- déjà ces valeurs : c'est user_preferences qui était en retard, pas l'app qui dérivait.
--
-- DÉCISION : on aligne user_preferences sur les 9 types RÉELLEMENT proposés par l'app.
-- On n'inclut PAS 'histogram'/'equivolume'/'renko' (présents dans chart_templates mais
-- absents de l'UI) ni le doublon 'heikin_ashi' (l'app envoie 'ha'), pour ne pas pérenniser
-- deux valeurs pour un même type.
--
-- INNOCUITÉ VÉRIFIÉE : au moment de l'écriture, user_preferences.default_chart_type ne
-- contient que 'candlestick' (1) et NULL (2) → aucune ligne existante ne peut violer la
-- nouvelle contrainte, qui est un SUR-ensemble de l'ancienne (sauf 'heikin_ashi'/'renko'
-- retirés, non utilisés par aucune ligne). Idempotent (DROP IF EXISTS avant ADD).

ALTER TABLE public.user_preferences
  DROP CONSTRAINT IF EXISTS user_preferences_default_chart_type_check;

ALTER TABLE public.user_preferences
  ADD CONSTRAINT user_preferences_default_chart_type_check
  CHECK (
    default_chart_type IS NULL
    OR default_chart_type = ANY (ARRAY[
      'bar', 'candlestick', 'hollowCandle', 'volCandles',
      'line', 'stepline', 'area', 'baseline', 'ha'
    ]::text[])
  );

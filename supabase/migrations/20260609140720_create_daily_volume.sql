-- 1. Création de la nouvelle table dédiée aux volumes
CREATE TABLE IF NOT EXISTS public.daily_volume (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    instrument_id uuid NOT NULL REFERENCES public.instruments(id) ON DELETE CASCADE,
    date date NOT NULL,
    quantity bigint NOT NULL,
    value numeric,
    trade_count integer,
    source text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    UNIQUE(instrument_id, date)
);

-- 2. (Étape de sécurité) Migration de l'historique des volumes de daily_candles vers daily_volume
-- On copie tous les volumes existants (avant de les supprimer de daily_candles) pour ne pas perdre l'historique d'avant le 19 mai.
INSERT INTO public.daily_volume (instrument_id, date, quantity, value, trade_count, source)
SELECT instrument_id, date, quantity, value, trade_count, source
FROM public.daily_candles
WHERE quantity IS NOT NULL AND quantity > 0
ON CONFLICT (instrument_id, date) DO NOTHING;

-- 3. Nettoyage de daily_candles : suppression définitive des colonnes de volume
ALTER TABLE public.daily_candles
DROP COLUMN IF EXISTS quantity,
DROP COLUMN IF EXISTS value,
DROP COLUMN IF EXISTS trade_count;

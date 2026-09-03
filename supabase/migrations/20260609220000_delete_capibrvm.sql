-- Suppression de l'instrument CAPIBRVM (Capitalisation BRVM) qui n'est pas un vrai indice tradable.
-- L'ON DELETE CASCADE supprimera également ses données historiques associées.

DELETE FROM public.instruments
WHERE symbol = 'CAPIBRVM';

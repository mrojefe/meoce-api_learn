-- Bug pré-existant : `pg_catalog.current_date` est une syntaxe invalide
-- (CURRENT_DATE est un mot-clé spécial SQL, pas un identifiant qualifiable
-- par schéma) — le planner échoue à la résolution de nom ("missing
-- FROM-clause entry for table pg_catalog") dès qu'une ligne est insérée
-- dans corporate_actions, QUEL QUE SOIT son type (la clause est parsée même
-- si le AND court-circuite à l'exécution). Conséquence : la table n'a JAMAIS
-- pu recevoir la moindre ligne depuis sa création — d'où les 0 lignes
-- observées, pas un simple choix de ne pas encore l'alimenter.
CREATE OR REPLACE FUNCTION public.update_instrument_status_on_ca()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF NEW.type = 'delisting'
     AND NEW.status = 'effective'
     AND NEW.effective_date IS NOT NULL
     AND NEW.effective_date <= CURRENT_DATE THEN
    UPDATE public.instruments SET status = 'delisted' WHERE id = NEW.instrument_id;
  ELSIF NEW.type = 'suspension'
        AND NEW.status = 'effective'
        AND NEW.effective_date IS NOT NULL
        AND NEW.effective_date <= CURRENT_DATE THEN
    UPDATE public.instruments SET status = 'suspended' WHERE id = NEW.instrument_id;
  END IF;
  RETURN NEW;
END;
$function$;

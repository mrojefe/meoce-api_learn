-- ============================================================================
-- CKOISSA — quiz quotidien en flip cards (section « Culture » du dashboard).
--
-- Additif pur : ne touche PAS `culture_items` (réservé au conte, à venir).
-- 3 tables : le corpus de questions, les scores (1/jour/user) et les signets.
--
-- SÉCURITÉ ANTI-TRICHE : `ckoissa_questions.correct_answer` ne doit JAMAIS
-- être exposé avant soumission. On ENABLE RLS sur les 3 tables SANS aucune
-- policy permissive → tout accès anon/authenticated via PostgREST est refusé.
-- Le seul accès est le service-role (routes Next.js verifyJWT), qui bypass la
-- RLS et qui, pour /today, sélectionne explicitement les colonnes sûres
-- (jamais correct_answer). Contrairement à `culture_items` (policy publique),
-- on ne peut pas ouvrir la lecture publique ici sans divulguer les réponses.
-- ============================================================================

-- ── Corpus de questions ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ckoissa_questions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type           TEXT NOT NULL CHECK (type IN ('reveal', 'truefalse', 'yesno', 'mcq')),
  question       TEXT NOT NULL,
  options        TEXT[],                 -- QCM uniquement (sinon NULL)
  correct_answer TEXT,                   -- index QCM ('0'..) / 'true'|'false' / 'oui'|'non' ; NULL pour reveal
  explication    TEXT NOT NULL,          -- verso de la carte (toujours présent)
  theme          TEXT NOT NULL,          -- tag affiché : BRVM, UEMOA, Produits...
  difficulte     INT NOT NULL DEFAULT 1 CHECK (difficulte BETWEEN 1 AND 3),
  source_url     TEXT,                   -- sourçage (exigence : faits vérifiables)
  source_domaine TEXT,
  actif          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ckoissa_questions_actif_idx ON ckoissa_questions(actif) WHERE actif = TRUE;
ALTER TABLE ckoissa_questions ENABLE ROW LEVEL SECURITY;
-- Aucune policy : accès service-role uniquement (voir en-tête).

-- ── Scores : 1 tentative par jour et par utilisateur ───────────────────────
CREATE TABLE IF NOT EXISTS ckoissa_scores (
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  quiz_date    DATE NOT NULL,
  score        INT NOT NULL,
  total        INT NOT NULL,
  answers      JSONB,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, quiz_date)
);
CREATE INDEX IF NOT EXISTS ckoissa_scores_date_idx ON ckoissa_scores(quiz_date, score DESC);
ALTER TABLE ckoissa_scores ENABLE ROW LEVEL SECURITY;

-- ── Signets (calqué sur user_news_bookmarks) ───────────────────────────────
CREATE TABLE IF NOT EXISTS ckoissa_saves (
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES ckoissa_questions(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, question_id)
);
ALTER TABLE ckoissa_saves ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- SEED — jeu de départ recherché et sourcé (faits STABLES, evergreen).
-- Sources : brvm.org, bceao.int, tresor.economie.gouv.fr, fr.wikipedia.org.
-- correct_answer pour QCM = INDEX (texte) de la bonne option dans `options`.
-- ============================================================================
INSERT INTO ckoissa_questions (type, question, options, correct_answer, explication, theme, difficulte, source_url, source_domaine) VALUES
-- ── BRVM ──
('mcq', 'En quelle année la BRVM a-t-elle démarré ses activités ?', ARRAY['1996','1998','2000','2004'], '1',
 'La Bourse Régionale des Valeurs Mobilières (BRVM) a démarré ses activités le 16 septembre 1998, à Abidjan.', 'BRVM', 1,
 'https://www.brvm.org/', 'brvm.org'),
('mcq', 'Combien de pays partagent la BRVM ?', ARRAY['5','7','8','10'], '2',
 'La BRVM est commune aux 8 pays de l''UEMOA : Bénin, Burkina Faso, Côte d''Ivoire, Guinée-Bissau, Mali, Niger, Sénégal et Togo.', 'BRVM', 1,
 'https://www.brvm.org/', 'brvm.org'),
('mcq', 'Dans quelle ville se trouve le siège de la BRVM ?', ARRAY['Dakar','Abidjan','Lomé','Cotonou'], '1',
 'Le siège de la BRVM est à Abidjan, en Côte d''Ivoire (18, rue Joseph Anoma).', 'BRVM', 1,
 'https://www.brvm.org/en/bureaux/headquarters', 'brvm.org'),
('truefalse', 'La variation quotidienne du cours d''une action à la BRVM est plafonnée à ±7,5 %.', NULL, 'true',
 'Vrai : le seuil de variation statique autorisé sur une séance est de ±7,5 %. En cotation continue s''ajoute un seuil de réservation dynamique de ±2 %.', 'BRVM', 2,
 'https://www.brvm.org/fr/marche-des-actions', 'brvm.org'),
('truefalse', 'La BRVM a son siège à Dakar.', NULL, 'false',
 'Faux : le siège de la BRVM est à Abidjan (Côte d''Ivoire). C''est la BCEAO qui a son siège à Dakar.', 'BRVM', 1,
 'https://www.brvm.org/en/bureaux/headquarters', 'brvm.org'),
('truefalse', 'La BRVM a été créée au service d''un seul pays.', NULL, 'false',
 'Faux : c''est une bourse RÉGIONALE, unique au monde à couvrir 8 États souverains sous une même réglementation et une monnaie commune.', 'BRVM', 1,
 'https://fr.wikipedia.org/wiki/Bourse_r%C3%A9gionale_des_valeurs_mobili%C3%A8res', 'wikipedia.org'),
('reveal', 'Que désigne l''indice « BRVM Composite » ?', NULL, NULL,
 'Le BRVM Composite reflète l''évolution de l''ENSEMBLE des sociétés cotées à la BRVM. C''est le baromètre large du marché.', 'BRVM', 1,
 'https://www.brvm.org/fr/indices', 'brvm.org'),
('reveal', 'Que regroupe l''indice « BRVM 30 » ?', NULL, NULL,
 'Le BRVM 30 regroupe les 30 valeurs les PLUS LIQUIDES du marché (les plus échangées sur un trimestre). Il sert d''indice de référence.', 'BRVM', 2,
 'https://www.brvm.org/fr/indices', 'brvm.org'),
('mcq', 'Quel indice ne retient que les valeurs les plus liquides de la BRVM ?', ARRAY['BRVM Composite','BRVM 30','BRVM Prestige','BRVM Total'], '1',
 'Le BRVM 30 sélectionne les 30 titres les plus liquides ; le BRVM Composite, lui, regroupe toutes les valeurs cotées.', 'BRVM', 2,
 'https://www.brvm.org/fr/indices', 'brvm.org'),
('yesno', 'La BRVM cote-t-elle des obligations en plus des actions ?', NULL, 'oui',
 'Oui : le marché comprend un compartiment actions ET un compartiment obligations (emprunts d''États et d''entreprises).', 'BRVM', 1,
 'https://www.brvm.org/', 'brvm.org'),
('yesno', 'La Côte d''Ivoire est-elle le pays qui accueille le siège de la BRVM ?', NULL, 'oui',
 'Oui : le siège est à Abidjan, en Côte d''Ivoire — le pays qui concentre la majeure partie de la capitalisation du marché.', 'BRVM', 1,
 'https://www.brvm.org/en/bureaux/headquarters', 'brvm.org'),
-- ── UEMOA / macro ──
('reveal', 'Que signifie le sigle « UEMOA » ?', NULL, NULL,
 'Union Économique et Monétaire Ouest-Africaine : 8 pays partageant une monnaie commune (le franc CFA) et une banque centrale (la BCEAO).', 'UEMOA', 1,
 'https://www.bceao.int/', 'bceao.int'),
('reveal', 'Que désigne la « BCEAO » ?', NULL, NULL,
 'La Banque Centrale des États de l''Afrique de l''Ouest : elle émet le franc CFA (XOF) et conduit la politique monétaire des 8 pays de l''UEMOA. Siège à Dakar.', 'UEMOA', 1,
 'https://www.bceao.int/', 'bceao.int'),
('mcq', 'Où se trouve le siège de la BCEAO ?', ARRAY['Abidjan','Dakar','Bamako','Ouagadougou'], '1',
 'Le siège de la BCEAO est à Dakar, au Sénégal.', 'UEMOA', 1,
 'https://www.bceao.int/', 'bceao.int'),
('mcq', 'Quelle est la parité fixe du franc CFA (XOF) avec l''euro ?', ARRAY['1 € = 500 XOF','1 € = 655,957 XOF','1 € = 700 XOF','1 € = 1000 XOF'], '1',
 '1 euro = 655,957 francs CFA. Cette parité est fixe depuis le lancement de l''euro (1999) et garantie par le Trésor français.', 'UEMOA', 2,
 'https://www.tresor.economie.gouv.fr/tresor-international/la-zone-franc', 'tresor.economie.gouv.fr'),
('truefalse', 'Le franc CFA de l''UEMOA porte le code ISO « XOF ».', NULL, 'true',
 'Vrai : XOF est le code de la monnaie des 8 pays de l''UEMOA. (Le franc CFA d''Afrique centrale, lui, porte le code XAF.)', 'UEMOA', 2,
 'https://fr.wikipedia.org/wiki/Franc_CFA_(UEMOA)', 'wikipedia.org'),
('yesno', 'Les 8 pays de l''UEMOA partagent-ils la même monnaie ?', NULL, 'oui',
 'Oui : ils utilisent tous le franc CFA (XOF), émis par la BCEAO — c''est le fondement de l''union monétaire.', 'UEMOA', 1,
 'https://www.bceao.int/', 'bceao.int'),
('mcq', 'Lequel de ces pays n''est PAS membre de l''UEMOA ?', ARRAY['Sénégal','Ghana','Mali','Togo'], '1',
 'Le Ghana n''est pas dans l''UEMOA (il a sa propre monnaie, le cedi). Les 8 membres sont Bénin, Burkina, Côte d''Ivoire, Guinée-Bissau, Mali, Niger, Sénégal, Togo.', 'UEMOA', 2,
 'https://www.bceao.int/', 'bceao.int'),
('yesno', 'La parité entre le franc CFA (XOF) et l''euro est-elle fixe ?', NULL, 'oui',
 'Oui : contrairement à une monnaie flottante, le XOF est arrimé à l''euro à un taux fixe (655,957), stable depuis 1999.', 'UEMOA', 1,
 'https://www.tresor.economie.gouv.fr/tresor-international/la-zone-franc', 'tresor.economie.gouv.fr'),
-- ── Produits & notions ──
('reveal', 'Qu''est-ce qu''une ACTION ?', NULL, NULL,
 'Une action est un titre de PROPRIÉTÉ : elle représente une part du capital d''une société. La détenir, c''est en devenir copropriétaire et avoir droit à une part des bénéfices.', 'Produits', 1,
 'https://www.brvm.org/fr/marche-des-actions', 'brvm.org'),
('reveal', 'Qu''est-ce qu''une OBLIGATION ?', NULL, NULL,
 'Une obligation est un titre de CRÉANCE : en l''achetant, on prête de l''argent à un émetteur (État ou entreprise) qui s''engage à rembourser avec des intérêts. Ce n''est pas une part de propriété.', 'Produits', 1,
 'https://www.brvm.org/', 'brvm.org'),
('reveal', 'Qu''est-ce qu''un DIVIDENDE ?', NULL, NULL,
 'Le dividende est la part du bénéfice qu''une société distribue à ses actionnaires. Il n''est ni obligatoire ni garanti : il dépend des résultats et de la décision de l''assemblée.', 'Produits', 1,
 'https://www.brvm.org/fr/marche-des-actions', 'brvm.org'),
('reveal', 'Que désigne un « OPCVM » ?', NULL, NULL,
 'Un Organisme de Placement Collectif en Valeurs Mobilières : un fonds qui met en commun l''argent de nombreux épargnants pour l''investir en actions/obligations, géré par un professionnel.', 'Produits', 2,
 'https://www.brvm.org/', 'brvm.org'),
('reveal', 'Que mesure le ratio « cours / bénéfice » (P/E) ?', NULL, NULL,
 'Le P/E indique combien un investisseur paie pour chaque franc de bénéfice généré par la société. Un P/E élevé traduit de fortes attentes de croissance.', 'Produits', 2,
 'https://www.brvm.org/', 'brvm.org'),
('truefalse', 'Une obligation représente une part de propriété de l''entreprise.', NULL, 'false',
 'Faux : une obligation est une DETTE (créance) — on prête de l''argent. C''est l''ACTION qui confère la propriété d''une part du capital.', 'Produits', 2,
 'https://www.brvm.org/', 'brvm.org'),
('truefalse', 'Le versement d''un dividende est garanti chaque année.', NULL, 'false',
 'Faux : le dividende dépend des bénéfices et d''une décision de l''entreprise. Une société peut décider de ne rien distribuer (pour réinvestir, ou faute de résultats).', 'Produits', 1,
 'https://www.brvm.org/fr/marche-des-actions', 'brvm.org'),
('mcq', 'La capitalisation boursière d''une société se calcule comment ?', ARRAY['Cours de l''action × nombre d''actions','Bénéfice net annuel','Chiffre d''affaires','Total des dettes'], '0',
 'Capitalisation boursière = cours de l''action × nombre d''actions en circulation. C''est la valeur que le marché attribue à toute la société.', 'Produits', 2,
 'https://www.brvm.org/fr/capitalisations/investisseurs/portefeuille', 'brvm.org'),
('mcq', 'Qu''est-ce qu''un OPCVM ?', ARRAY['Un impôt de bourse','Un fonds de placement collectif','Une obligation d''État','Une banque centrale'], '1',
 'Un OPCVM est un fonds qui met en commun l''épargne de plusieurs investisseurs pour l''investir de façon diversifiée et professionnelle.', 'Produits', 1,
 'https://www.brvm.org/', 'brvm.org'),
('yesno', 'Acheter une action, est-ce devenir copropriétaire de l''entreprise ?', NULL, 'oui',
 'Oui : l''action est un titre de propriété. En détenir, c''est posséder une fraction du capital de la société et de ses résultats futurs.', 'Produits', 1,
 'https://www.brvm.org/fr/marche-des-actions', 'brvm.org'),
('yesno', 'Un actionnaire peut-il recevoir un dividende ?', NULL, 'oui',
 'Oui : quand la société distribue une partie de ses bénéfices, chaque actionnaire reçoit un dividende proportionnel au nombre d''actions détenues.', 'Produits', 1,
 'https://www.brvm.org/fr/marche-des-actions', 'brvm.org');

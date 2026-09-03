-- ============================================================
-- Migration : extensions schéma AfriView V2 — données GOLD BOC
-- Date      : 2026-05-29
-- Scope     : modifications de tables existantes + nouvelle table bond_details
--
-- Ce fichier contient UNIQUEMENT des changements de schéma (DDL).
-- L'injection des données est gérée par les scripts Python séparés :
--   inject_instruments.py, inject_dividendes.py, inject_corporate_events.py
--
-- Sections :
--   1. dividends        — rendre declaration_date nullable + nouvelle UNIQUE
--                         + ajout colonnes manquantes
--   2. corporate_actions — rendre announcement_date nullable
--                         + UNIQUE pour idempotence injection
--   3. instruments      — ajout colonnes historiques BOC + données IPO
--   4. bond_details     — nouvelle table pour attributs spécifiques obligations
-- ============================================================


-- ============================================================
-- SECTION 1 — TABLE dividends
-- ============================================================
-- Contexte :
--   GOLD_ACTION_DIVIDENDE.csv (562 lignes) → table dividends
--   Problèmes identifiés avant injection :
--
--   A) declaration_date DATE NOT NULL :
--      550/562 dividendes historiques BOC n'ont PAS de declaration_date.
--      Seule la payment_date est systématiquement disponible.
--
--   B) UNIQUE (instrument_id, declaration_date, type) inutilisable :
--      PostgreSQL : NULL ≠ NULL → la contrainte ne protège pas contre
--      les doublons quand declaration_date est NULL.
--      Nouvelle clé naturelle : (instrument_id, payment_date, type).
--
--   C) Colonnes manquantes par rapport au GOLD :
--      amount_raw        : valeur publiée BOC pré-split (diffère de amount
--                          pour 288 dividendes split-adjustés)
--      gross_amount      : montant brut avant retenue (step 5, mostly NULL)
--      dividend_type     : ordinary / complementary / exceptional
--                          (FTSC 2025-09-30 a un ordinaire + exceptionnel
--                           le même jour — distingués par ce champ)
--      resolution        : qualité pipeline Silver→Gold
--                          (format / split_adjusted_format /
--                           amount_correction / annuaire_2013 /
--                           hardcoded_2rows / annuaire_2013_investigate)
--      normalization_log : JSONB traçabilité complète
--                          {silver_mode, silver_n_obs, silver_n_unique,
--                           splits_applied:[{factor, split_date, auto}],
--                           manual_override}
-- ============================================================

-- 1.A : rendre declaration_date nullable
ALTER TABLE dividends
  ALTER COLUMN declaration_date DROP NOT NULL;

-- 1.B : remplacer la contrainte UNIQUE
ALTER TABLE dividends
  DROP CONSTRAINT IF EXISTS dividends_instrument_id_declaration_date_type_key;

-- 1.C : ajouter les colonnes manquantes (avant la création de l'index qui référence dividend_type)
ALTER TABLE dividends
  ADD COLUMN IF NOT EXISTS amount_raw         NUMERIC(18,6),
  ADD COLUMN IF NOT EXISTS gross_amount       NUMERIC(18,6),
  ADD COLUMN IF NOT EXISTS dividend_type      TEXT
    CHECK (dividend_type IS NULL
        OR dividend_type IN ('ordinary','complementary','exceptional')),
  ADD COLUMN IF NOT EXISTS resolution         TEXT,
  ADD COLUMN IF NOT EXISTS normalization_log  JSONB;

-- 1.D : créer l'index UNIQUE (après ADD COLUMN dividend_type)
CREATE UNIQUE INDEX IF NOT EXISTS uniq_dividends_instrument_payment_type
  ON dividends(instrument_id, payment_date, type, COALESCE(dividend_type, ''))
  WHERE payment_date IS NOT NULL;

-- Index utiles dividends
CREATE INDEX IF NOT EXISTS idx_dividends_payment_date
  ON dividends(payment_date) WHERE payment_date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_dividends_resolution
  ON dividends(resolution) WHERE resolution IS NOT NULL;


-- ============================================================
-- SECTION 2 — TABLE corporate_actions
-- ============================================================
-- Contexte :
--   GOLD_ACTION_CORPORATE_EVENTS.csv (68 lignes injectables) → corporate_actions
--
--   A) announcement_date DATE NOT NULL :
--      Événements historiques BRVM documentés par date effective uniquement.
--      La date d'annonce exacte n'est pas disponible dans les données sources.
--
--   B) Pas de UNIQUE sur (instrument_id, effective_date, type) :
--      Sans UNIQUE, un re-run du script d'injection crée des doublons.
--      On ajoute un index UNIQUE partiel pour protéger les injections.
-- ============================================================

-- 2.A : rendre announcement_date nullable
ALTER TABLE corporate_actions
  ALTER COLUMN announcement_date DROP NOT NULL;

-- 2.B : UNIQUE pour idempotence (partiel : seulement si effective_date IS NOT NULL)
CREATE UNIQUE INDEX IF NOT EXISTS uniq_corporate_actions_instrument_date_type
  ON corporate_actions(instrument_id, effective_date, type)
  WHERE effective_date IS NOT NULL;


-- ============================================================
-- SECTION 3 — TABLE instruments
-- ============================================================
-- Contexte :
--   BRONZE_ACTION_IDENTITE.csv (53 lignes) + RAW_PREMIER_COURS_BRVM.csv (48 lignes)
--   contiennent des données absentes du schéma initial.
--
--   ticker_boc        : nom BOC (peut différer du nom officiel)
--                       ex: "SERVAIR ABIDJAN CI" (BOC) vs
--                           "SERVAIR ABIDJAN COTE D'IVOIRE" (DB)
--   cap_class         : classe de capitalisation BRVM (A/B/C/D)
--                       A=grande cap, B=moyenne, C=petite, D=micro
--   market_tier       : compartiment ('1er', '2eme')
--   first_listed_at   : première apparition dans le BOC (données locales 2009+)
--                       ≠ listing_date (admission officielle, peut être antérieure)
--   last_listed_at    : dernière apparition dans le BOC
--                       Pour instruments suspendus/délistés : fin d'observation
--   boc_session_count : nombre de sessions cotées dans le BOC (2009→2026)
--   listing_date      : date d'admission officielle BRVM
--                       Renseigné pour 28/53 actions (reste non documenté)
--   listing_price     : prix d'introduction/OPV en FCFA
--                       ex: BICC=23500 (1998), BICB=5250 (2025)
--   listing_source    : source de listing_date et listing_price (URL ou id)
--   listing_notes     : notes textuelles sur l'introduction
--                       ex: "Ancien nom BICICI. Transfert ex-BVA. Split ×10 oct 2017."
-- ============================================================

ALTER TABLE instruments
  ADD COLUMN IF NOT EXISTS ticker_boc         TEXT,
  ADD COLUMN IF NOT EXISTS cap_class          CHAR(1)
    CHECK (cap_class IS NULL OR cap_class IN ('A','B','C','D')),
  ADD COLUMN IF NOT EXISTS market_tier        TEXT
    CHECK (market_tier IS NULL OR market_tier IN ('1er','2eme')),
  ADD COLUMN IF NOT EXISTS first_listed_at    DATE,
  ADD COLUMN IF NOT EXISTS last_listed_at     DATE,
  ADD COLUMN IF NOT EXISTS boc_session_count  INT
    CHECK (boc_session_count IS NULL OR boc_session_count >= 0),
  ADD COLUMN IF NOT EXISTS listing_date       DATE,
  ADD COLUMN IF NOT EXISTS listing_price      NUMERIC(18,2),
  ADD COLUMN IF NOT EXISTS listing_source     TEXT,
  ADD COLUMN IF NOT EXISTS listing_notes      TEXT;

-- Index instruments
CREATE INDEX IF NOT EXISTS idx_instruments_cap_class
  ON instruments(cap_class) WHERE cap_class IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_instruments_market_tier
  ON instruments(market_tier) WHERE market_tier IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_instruments_listing_date
  ON instruments(listing_date) WHERE listing_date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_instruments_first_listed
  ON instruments(first_listed_at) WHERE first_listed_at IS NOT NULL;


-- ============================================================
-- SECTION 4 — TABLE bond_details (nouvelle)
-- ============================================================
-- Contexte :
--   UNIFY_OBLIGATIONS.csv (282 321 lignes, 307 symboles obligataires)
--   contient des attributs spécifiques aux obligations absents de instruments.
--
--   Table séparée (FK 1-1 → instruments) car ces colonnes sont :
--   - requêtées pour filtrer (bond_type, pays_emetteur, maturity_date)
--   - utilisées pour des calculs (coupon couru, yield to maturity)
--   - distinctes sémantiquement des attributs génériques d'un instrument
--
--   Champs :
--   face_value         : valeur nominale (10 000 FCFA pour la plupart des obligations BRVM)
--   coupon_rate        : taux d'intérêt annuel (ex: 0.0560 pour 5,60%)
--   coupon_amount      : montant annuel par titre en FCFA (depuis coupon_montant BOC)
--   coupon_frequency   : fréquence de paiement des coupons
--   issue_date         : date d'émission
--   maturity_date      : date d'échéance principale (date_echeance_1 BOC)
--   maturity_date_2    : date d'échéance secondaire si tranche (date_echeance_2)
--   bond_type          : classification BOC (STANDARD/REGIONALE/KOLAS/INTERNATIONALE/SUKUK)
--   bond_category      : catégorie financière (_bond_type BOC classifier)
--                        Sovereign Bond / Corporate Bond / Supranational Bond /
--                        GSS Bond / FCTC / Convertible Bond / Sukuk / KOLAS
--   emetteur_type      : type d'émetteur (_emetteur_type BOC classifier)
--   pays_emetteur      : pays de l'émetteur (_pays BOC classifier)
--   outstanding_amount : encours (peut diminuer avec rachats partiels)
-- ============================================================

CREATE TABLE IF NOT EXISTS bond_details (
  instrument_id         UUID          PRIMARY KEY
                                      REFERENCES instruments(id) ON DELETE CASCADE,

  -- Caractéristiques financières fondamentales
  face_value            NUMERIC(18,2),
  coupon_rate           NUMERIC(6,4),
  coupon_amount         NUMERIC(18,4),
  coupon_frequency      TEXT
    CHECK (coupon_frequency IS NULL
        OR coupon_frequency IN ('annual','semi_annual','quarterly')),

  -- Dates
  issue_date            DATE,
  maturity_date         DATE,
  maturity_date_2       DATE,

  -- Classification BRVM
  bond_type             TEXT
    CHECK (bond_type IS NULL
        OR bond_type IN ('STANDARD','REGIONALE','KOLAS','INTERNATIONALE','SUKUK')),
  bond_category         TEXT,
  emetteur_type         TEXT,
  pays_emetteur         TEXT,

  -- Encours
  outstanding_amount    NUMERIC(18,2),

  -- Source
  source                TEXT,

  -- Audit
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bond_details_maturity
  ON bond_details(maturity_date) WHERE maturity_date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bond_details_bond_type
  ON bond_details(bond_type) WHERE bond_type IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bond_details_bond_category
  ON bond_details(bond_category) WHERE bond_category IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bond_details_pays
  ON bond_details(pays_emetteur) WHERE pays_emetteur IS NOT NULL;

DROP TRIGGER IF EXISTS trg_bond_details_updated_at ON bond_details;
CREATE TRIGGER trg_bond_details_updated_at
  BEFORE UPDATE ON bond_details
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS — lecture publique
ALTER TABLE bond_details ENABLE ROW LEVEL SECURITY;
CREATE POLICY read_all ON bond_details FOR SELECT USING (true);


-- ============================================================
-- SECTION 5 — TABLE bond_candles (nouvelle)
-- ============================================================
-- Contexte :
--   Données journalières spécifiques aux obligations.
--   Le carnet d'ordres (bid/ask/reference_price/trading_status) va dans
--   daily_order_book (table existante, générique).
--   bond_candles stocke ce que daily_order_book ne couvre pas :
--     close_price    : cours coté ce jour (non-null seulement si status=Marché,
--                      ~60 dates sur 282 321 lignes BOC)
--     coupon_couru   : intérêts courus en FCFA à cette date
--     coupon_montant : montant annuel du coupon à cette date
--                      (varie pour les ACD — capital décroissant)
--     volume_valeur  : volume en FCFA (rare, surtout obligations souveraines)
--     nbr_transaction: nombre de transactions (rare)
--
--   PK (instrument_id, date) — cohérente avec daily_candles et daily_order_book.
-- ============================================================

CREATE TABLE IF NOT EXISTS bond_candles (
  instrument_id     UUID          NOT NULL
                                  REFERENCES instruments(id) ON DELETE CASCADE,
  date              DATE          NOT NULL,

  -- Prix coté (seulement quand l'obligation est effectivement traitée)
  close_price       NUMERIC(18,4),

  -- Coupon couru en FCFA à cette date de séance
  coupon_couru      NUMERIC(18,4),

  -- Montant annuel du coupon à cette date (pour ACD : décroît avec le capital)
  coupon_montant    NUMERIC(18,4),

  -- Volume (bfin priority, sinon BOC)
  volume_titre      BIGINT        CHECK (volume_titre IS NULL OR volume_titre >= 0),
  volume_valeur     NUMERIC(18,2),
  nbr_transaction   INT           CHECK (nbr_transaction IS NULL OR nbr_transaction >= 0),

  -- Traçabilité
  source            TEXT          NOT NULL DEFAULT 'boc_pdf'
                                  CHECK (source IN ('boc_pdf')),
  boc_format_model  TEXT,

  -- Audit
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),

  PRIMARY KEY (instrument_id, date)
);

CREATE INDEX IF NOT EXISTS idx_bond_candles_date
  ON bond_candles(date DESC);

DROP TRIGGER IF EXISTS trg_bond_candles_updated_at ON bond_candles;
CREATE TRIGGER trg_bond_candles_updated_at
  BEFORE UPDATE ON bond_candles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS — lecture publique
ALTER TABLE bond_candles ENABLE ROW LEVEL SECURITY;
CREATE POLICY read_all ON bond_candles FOR SELECT USING (true);


-- ============================================================
-- SECTION 6 — TABLE right_details (nouvelle)
-- ============================================================
-- Contexte :
--   21 droits BRVM (DS + DA) cotés entre 2009 et 2026.
--   Attributs statiques spécifiques aux droits, absents de instruments.
--
--   droit_type           : DS = Droit de Souscription (subscription right)
--                          DA = Droit d'Attribution (attribution right)
--   parent_instrument_id : FK vers l'action sous-jacente (nullable — résolu
--                          lors de l'injection par lookup sur parent_symbol)
--   parent_symbol        : symbole de l'action parente (ex: BOAN pour BOAN.DS5)
--                          Conservé en texte pour résilience en cas de
--                          parent non encore présent en DB
--   ratio_texte          : ratio de souscription/attribution tel que publié
--                          dans le BOC (ex: "9 pour 1", "1/2", "Une (1) action
--                          nouvelle pour 16 actions anciennes.")
--                          NULL pour SVOC.DS1 (ratio non capturé en source)
--   date_debut           : premier jour de cotation du droit
--   date_fin             : dernier jour de cotation du droit (expiry)
-- ============================================================

CREATE TABLE IF NOT EXISTS right_details (
  instrument_id         UUID          PRIMARY KEY
                                      REFERENCES instruments(id) ON DELETE CASCADE,

  -- Type de droit BRVM
  droit_type            TEXT
    CHECK (droit_type IS NULL OR droit_type IN ('DS', 'DA')),

  -- Lien vers l'action sous-jacente
  parent_instrument_id  UUID
    REFERENCES instruments(id),         -- nullable : résolu à l'injection
  parent_symbol         TEXT,           -- backup texte

  -- Caractéristiques de l'opération
  ratio_texte           TEXT,           -- tel que publié dans le BOC
  date_debut            DATE,
  date_fin              DATE,

  -- Source
  source                TEXT,

  -- Audit
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_right_details_parent
  ON right_details(parent_instrument_id) WHERE parent_instrument_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_right_details_parent_symbol
  ON right_details(parent_symbol) WHERE parent_symbol IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_right_details_date_fin
  ON right_details(date_fin) WHERE date_fin IS NOT NULL;

DROP TRIGGER IF EXISTS trg_right_details_updated_at ON right_details;
CREATE TRIGGER trg_right_details_updated_at
  BEFORE UPDATE ON right_details
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS — lecture publique
ALTER TABLE right_details ENABLE ROW LEVEL SECURITY;
CREATE POLICY read_all ON right_details FOR SELECT USING (true);


-- ============================================================
-- SECTION 7 — TABLE right_candles (nouvelle)
-- ============================================================
-- Contexte :
--   Données journalières de cotation des droits BRVM.
--   Table dédiée (analogie avec bond_candles) plutôt que daily_candles car :
--   - Les droits ont des champs spécifiques (reference_price, trading_status)
--     que daily_candles n'a pas nécessairement
--   - Le volume de données est très petit (275 lignes) — mieux isolé
--   - Facilite les requêtes par instrument_type=right sans JOIN
--
--   M1 (2009-2011) : close_price + trading_status (NC/SP)
--   M2 DS (2013-2026) : close_price + volume + volume_valeur + reference_price
--   M2 DA (2024) : close_price + volume + volume_valeur + reference_price
--                  (sur jours de transaction uniquement)
--
--   PK (instrument_id, date) — cohérente avec bond_candles et daily_candles.
-- ============================================================

CREATE TABLE IF NOT EXISTS right_candles (
  instrument_id     UUID          NOT NULL
                                  REFERENCES instruments(id) ON DELETE CASCADE,
  date              DATE          NOT NULL,

  -- Prix
  close_price       NUMERIC(18,4),
  open_price        NUMERIC(18,4),

  -- Volume
  volume            INT           CHECK (volume IS NULL OR volume >= 0),
  volume_valeur     NUMERIC(18,2),

  -- Référence et statut
  reference_price   NUMERIC(18,4),
  trading_status    TEXT          CHECK (trading_status IS NULL
                                    OR trading_status IN ('NC', 'SP', 'DIF', 'Marché')),

  -- Traçabilité
  source            TEXT          NOT NULL DEFAULT 'boc_pdf',
  boc_format_model  TEXT,

  -- Audit
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),

  PRIMARY KEY (instrument_id, date)
);

CREATE INDEX IF NOT EXISTS idx_right_candles_date
  ON right_candles(date DESC);

DROP TRIGGER IF EXISTS trg_right_candles_updated_at ON right_candles;
CREATE TRIGGER trg_right_candles_updated_at
  BEFORE UPDATE ON right_candles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS — lecture publique
ALTER TABLE right_candles ENABLE ROW LEVEL SECURITY;
CREATE POLICY read_all ON right_candles FOR SELECT USING (true);


-- ============================================================
-- SECTION 8 — TABLE daily_candles (extension CHECK source pipeline madis/bfin)
-- ============================================================
-- Contexte :
--   GOLD_ACTION_COTATION.csv (160 429 lignes, 1998→2026) — pipeline simplifié :
--     madis (BRVM_equity_COMPLET_1998_2026.csv) : OHLCV complet, 0 NULL → source canonique
--     bfin (brvm_traded_securities.csv)         : volumes (traded_volume/number_of_trades/traded_value)
--     5 radiés (CDAC/PHC/SGCC/SRIC/TTRC)       : instrument_id NULL → skippés à l'injection
--
--   Nouvelles valeurs source injectées :
--     madisinvest      : madis seul (6 563 lignes, dates 1998-2003 hors couverture bfin)
--     madisinvest+bfin : madis OHLCV + bfin volumes (147 584 lignes — 92% du Gold)
--
--   OHLC NOT NULL est conservé (madis = 0 NULL OHLCV → contrainte respectée).
-- ============================================================

ALTER TABLE daily_candles
  DROP CONSTRAINT IF EXISTS daily_candles_source_check;

ALTER TABLE daily_candles
  ADD CONSTRAINT daily_candles_source_check
  CHECK (source = ANY (ARRAY[
    'sikafinance',
    'sgi_eod',
    'boc_pdf',
    'manual',
    'other',
    'sikafinance+enriched_trade_sec',
    'sikafinance+recalc_close_x_qty',
    'madisinvest',
    'madisinvest+bfin'
  ]::text[]));

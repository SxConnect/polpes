-- ==========================================================================
-- Seed PostgreSQL — Polpes (cardápio digital + clube de fidelidade)
-- Gerado de: migração SQLite -> PostgreSQL concluída (2.147 linhas / 25 tabelas)
-- Data: 2026-10-30 22:50
--
-- AUTOSSUFICIENTE: cria o schema e popula. IDEMPOTENTE — pode rodar
-- quantas vezes precisar (INSERT ... ON CONFLICT DO NOTHING).
--
-- CONTEÚDO DE NEGÓCIO APENAS. NÃO contém:
--   • dados de cliente (contacts, messages, executions, orders, club_members)
--   • segredos (ai_api_key, openrouter_api_key, web_password_hash/salt)
--   • marcador de runtime (db_migrated_from_sqlite)
--
-- Como aplicar (stack de pé):
--   docker cp seed/polpes-seed.postgres.sql polpes-db:/tmp/seed.sql
--   docker exec -i polpes-db psql -U polpes -d polpes < /tmp/seed.sql
--   docker restart polpes
-- ==========================================================================

BEGIN;

-- ----------------------------------------------------------------------
-- Schema
-- ----------------------------------------------------------------------

-- Schema Postgres para o WhatsBot / Polpê's.
-- Equivalente a db/schema.sql (SQLite) + todas as colunas que no SQLite eram
-- aplicadas por _run_migrations. Aqui já vêm prontas, porque um banco Postgres
-- novo nasce completo.
--
-- Traduções: INTEGER PRIMARY KEY AUTOINCREMENT -> SERIAL PRIMARY KEY
--            REAL -> DOUBLE PRECISION

CREATE TABLE IF NOT EXISTS config (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS contacts (
    id              SERIAL PRIMARY KEY,
    phone           TEXT    NOT NULL UNIQUE,
    name            TEXT    NOT NULL DEFAULT '',
    email           TEXT    NOT NULL DEFAULT '',
    profession      TEXT    NOT NULL DEFAULT '',
    company         TEXT    NOT NULL DEFAULT '',
    address         TEXT    NOT NULL DEFAULT '',
    ai_enabled      INTEGER NOT NULL DEFAULT 1,
    bloqueado       INTEGER NOT NULL DEFAULT 0,
    is_group        INTEGER NOT NULL DEFAULT 0,
    group_name      TEXT    NOT NULL DEFAULT '',
    is_archived     INTEGER NOT NULL DEFAULT 0,
    archived_by_app INTEGER NOT NULL DEFAULT 0,
    can_send        INTEGER NOT NULL DEFAULT 1,
    unread_count    INTEGER NOT NULL DEFAULT 0,
    unread_ai_count INTEGER NOT NULL DEFAULT 0,
    delivery_cep    TEXT    NOT NULL DEFAULT '',
    last_greeting_date TEXT NOT NULL DEFAULT '',
    created_at      DOUBLE PRECISION NOT NULL,
    updated_at      DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_contacts_updated ON contacts(updated_at);
CREATE INDEX IF NOT EXISTS idx_contacts_archived ON contacts(is_archived);

CREATE TABLE IF NOT EXISTS observations (
    id         SERIAL PRIMARY KEY,
    contact_id INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    text       TEXT    NOT NULL,
    created_at DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_obs_contact ON observations(contact_id);

CREATE TABLE IF NOT EXISTS messages (
    id         SERIAL PRIMARY KEY,
    contact_id INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    role       TEXT    NOT NULL,
    content    TEXT    NOT NULL DEFAULT '',
    ts         DOUBLE PRECISION NOT NULL,
    media_type TEXT,
    media_path TEXT,
    status     TEXT,
    msg_id     TEXT
);
CREATE INDEX IF NOT EXISTS idx_msg_contact_ts ON messages(contact_id, ts);
CREATE INDEX IF NOT EXISTS idx_msg_id ON messages(msg_id);

CREATE TABLE IF NOT EXISTS usage (
    id                SERIAL PRIMARY KEY,
    contact_id        INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    call_type         TEXT    NOT NULL,
    model             TEXT    NOT NULL,
    prompt_tokens     INTEGER NOT NULL DEFAULT 0,
    completion_tokens INTEGER NOT NULL DEFAULT 0,
    total_tokens      INTEGER NOT NULL DEFAULT 0,
    cost_usd          DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    ts                DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_usage_contact_ts ON usage(contact_id, ts);
CREATE INDEX IF NOT EXISTS idx_usage_ts ON usage(ts);

CREATE TABLE IF NOT EXISTS tags (
    id    SERIAL PRIMARY KEY,
    name  TEXT    NOT NULL UNIQUE,
    color TEXT    NOT NULL
);

CREATE TABLE IF NOT EXISTS contact_tags (
    contact_id INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    tag_id     INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (contact_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_ct_tag ON contact_tags(tag_id);

CREATE TABLE IF NOT EXISTS unread_msg_ids (
    id         SERIAL PRIMARY KEY,
    contact_id INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    msg_id     TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_unread_contact ON unread_msg_ids(contact_id);

CREATE TABLE IF NOT EXISTS executions (
    id           SERIAL PRIMARY KEY,
    phone        TEXT    NOT NULL,
    trigger_type TEXT    NOT NULL DEFAULT 'webhook',
    status       TEXT    NOT NULL DEFAULT 'running',
    started_at   DOUBLE PRECISION NOT NULL,
    completed_at DOUBLE PRECISION,
    error        TEXT
);
CREATE INDEX IF NOT EXISTS idx_exec_started ON executions(started_at);

CREATE TABLE IF NOT EXISTS execution_steps (
    id           SERIAL PRIMARY KEY,
    execution_id INTEGER NOT NULL REFERENCES executions(id) ON DELETE CASCADE,
    step_type    TEXT    NOT NULL,
    status       TEXT    NOT NULL DEFAULT 'ok',
    data         TEXT,
    ts           DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_step_exec ON execution_steps(execution_id);

-- Clube Sabores Polpê's: assinantes e indicações
CREATE TABLE IF NOT EXISTS club_members (
    id                   SERIAL PRIMARY KEY,
    contact_id           INTEGER NOT NULL UNIQUE REFERENCES contacts(id) ON DELETE CASCADE,
    referral_code        TEXT    NOT NULL UNIQUE,
    referred_by_code     TEXT,
    status               TEXT    NOT NULL DEFAULT 'pending',
    plan_price           DOUBLE PRECISION NOT NULL DEFAULT 19.90,
    joined_at            DOUBLE PRECISION NOT NULL,
    payment_confirmed_at DOUBLE PRECISION,
    expires_at           DOUBLE PRECISION,
    cancelled_at         DOUBLE PRECISION,
    rewards_delivered    INTEGER NOT NULL DEFAULT 0,
    notes                TEXT    NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_club_contact ON club_members(contact_id);
CREATE INDEX IF NOT EXISTS idx_club_referral_code ON club_members(referral_code);
CREATE INDEX IF NOT EXISTS idx_club_referred_by ON club_members(referred_by_code);
CREATE INDEX IF NOT EXISTS idx_club_status ON club_members(status);
CREATE INDEX IF NOT EXISTS idx_club_expires ON club_members(expires_at);

-- Catálogo: categorias, produtos, formas de pagamento e pedidos
CREATE TABLE IF NOT EXISTS product_categories (
    id           SERIAL PRIMARY KEY,
    name         TEXT    NOT NULL UNIQUE,
    sort_order   INTEGER NOT NULL DEFAULT 0,
    active       INTEGER NOT NULL DEFAULT 1,
    needs_config INTEGER NOT NULL DEFAULT 0,
    is_addon     INTEGER NOT NULL DEFAULT 0,
    created_at   DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_categories_active ON product_categories(active);

CREATE TABLE IF NOT EXISTS category_addons (
    id                SERIAL PRIMARY KEY,
    category_id       INTEGER NOT NULL REFERENCES product_categories(id) ON DELETE CASCADE,
    addon_category_id INTEGER NOT NULL REFERENCES product_categories(id) ON DELETE CASCADE,
    min_select        INTEGER NOT NULL DEFAULT 0,
    max_select        INTEGER NOT NULL DEFAULT 0,
    free_qty          INTEGER NOT NULL DEFAULT 0,
    sort_order        INTEGER NOT NULL DEFAULT 0,
    active            INTEGER NOT NULL DEFAULT 1,
    created_at        DOUBLE PRECISION NOT NULL,
    UNIQUE(category_id, addon_category_id)
);
CREATE INDEX IF NOT EXISTS idx_category_addons_category
    ON category_addons(category_id, active, sort_order);

CREATE TABLE IF NOT EXISTS products (
    id          SERIAL PRIMARY KEY,
    category_id INTEGER NOT NULL REFERENCES product_categories(id) ON DELETE CASCADE,
    name        TEXT    NOT NULL,
    description TEXT    NOT NULL DEFAULT '',
    price       DOUBLE PRECISION NOT NULL DEFAULT 0,
    promo_price DOUBLE PRECISION NOT NULL DEFAULT 0,
    club_price  DOUBLE PRECISION NOT NULL DEFAULT 0,
    photo_path  TEXT    NOT NULL DEFAULT '',
    sort_order  INTEGER NOT NULL DEFAULT 0,
    active      INTEGER NOT NULL DEFAULT 1,
    in_stock    INTEGER NOT NULL DEFAULT 1,
    created_at  DOUBLE PRECISION NOT NULL,
    updated_at  DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_active ON products(active);

CREATE TABLE IF NOT EXISTS payment_methods (
    id           SERIAL PRIMARY KEY,
    method_type  TEXT    NOT NULL,
    label        TEXT    NOT NULL,
    instructions TEXT    NOT NULL DEFAULT '',
    active       INTEGER NOT NULL DEFAULT 1,
    sort_order   INTEGER NOT NULL DEFAULT 0,
    pix_key      TEXT    NOT NULL DEFAULT '',
    pix_name     TEXT    NOT NULL DEFAULT '',
    pix_city     TEXT    NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS orders (
    id                SERIAL PRIMARY KEY,
    contact_id        INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    status            TEXT    NOT NULL DEFAULT 'aberto',
    payment_method_id INTEGER REFERENCES payment_methods(id),
    needs_change      INTEGER,
    change_for_amount DOUBLE PRECISION,
    total             DOUBLE PRECISION NOT NULL DEFAULT 0,
    notes             TEXT    NOT NULL DEFAULT '',
    delivered_at      DOUBLE PRECISION,
    review_requested_at DOUBLE PRECISION,
    created_at        DOUBLE PRECISION NOT NULL,
    updated_at        DOUBLE PRECISION NOT NULL,
    delivery_fee      DOUBLE PRECISION NOT NULL DEFAULT 0,
    delivery_distance_km DOUBLE PRECISION,
    delivery_cep      TEXT    NOT NULL DEFAULT '',
    delivery_cidade   TEXT    NOT NULL DEFAULT '',
    coupon_code       TEXT    NOT NULL DEFAULT '',
    discount          DOUBLE PRECISION NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_orders_contact ON orders(contact_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

CREATE TABLE IF NOT EXISTS order_items (
    id            SERIAL PRIMARY KEY,
    order_id      INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id    INTEGER REFERENCES products(id),
    product_name  TEXT    NOT NULL,
    unit_price    DOUBLE PRECISION NOT NULL,
    quantity      INTEGER NOT NULL DEFAULT 1,
    subtotal      DOUBLE PRECISION NOT NULL,
    options_json  TEXT    NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

CREATE TABLE IF NOT EXISTS club_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS club_benefits (
    id          SERIAL PRIMARY KEY,
    name        TEXT    NOT NULL,
    description TEXT    NOT NULL DEFAULT '',
    active      INTEGER NOT NULL DEFAULT 1,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  DOUBLE PRECISION NOT NULL,
    updated_at  DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_club_benefits_active ON club_benefits(active, sort_order);

CREATE TABLE IF NOT EXISTS club_conditions (
    id          SERIAL PRIMARY KEY,
    title       TEXT    NOT NULL,
    detail      TEXT    NOT NULL DEFAULT '',
    active      INTEGER NOT NULL DEFAULT 1,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  DOUBLE PRECISION NOT NULL,
    updated_at  DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_club_conditions_active ON club_conditions(active, sort_order);

CREATE TABLE IF NOT EXISTS coupons (
    id             SERIAL PRIMARY KEY,
    code           TEXT    NOT NULL UNIQUE,
    description    TEXT    NOT NULL DEFAULT '',
    discount_type  TEXT    NOT NULL DEFAULT 'percent',
    discount_value DOUBLE PRECISION NOT NULL DEFAULT 0,
    min_order      DOUBLE PRECISION NOT NULL DEFAULT 0,
    max_uses       INTEGER NOT NULL DEFAULT 0,
    used_count     INTEGER NOT NULL DEFAULT 0,
    member_only    INTEGER NOT NULL DEFAULT 0,
    active         INTEGER NOT NULL DEFAULT 1,
    expires_at     DOUBLE PRECISION,
    created_at     DOUBLE PRECISION NOT NULL,
    updated_at     DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_coupons_active ON coupons(active);

CREATE TABLE IF NOT EXISTS coupon_redemptions (
    id         SERIAL PRIMARY KEY,
    coupon_id  INTEGER NOT NULL REFERENCES coupons(id) ON DELETE CASCADE,
    contact_id INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    order_id   INTEGER,
    amount     DOUBLE PRECISION NOT NULL DEFAULT 0,
    created_at DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_coupon ON coupon_redemptions(coupon_id);
CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_contact ON coupon_redemptions(contact_id);

CREATE TABLE IF NOT EXISTS chat_sessions (
    session_id TEXT PRIMARY KEY,
    contact_id INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    name       TEXT    NOT NULL DEFAULT '',
    phone      TEXT    NOT NULL DEFAULT '',
    created_at DOUBLE PRECISION NOT NULL,
    updated_at DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_chat_sessions_contact ON chat_sessions(contact_id);

CREATE TABLE IF NOT EXISTS delivery_zones (
    id          SERIAL PRIMARY KEY,
    ate_km      DOUBLE PRECISION NOT NULL,
    taxa        DOUBLE PRECISION NOT NULL DEFAULT 0,
    ativo       INTEGER NOT NULL DEFAULT 1,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  DOUBLE PRECISION NOT NULL,
    updated_at  DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_delivery_zones_ativo ON delivery_zones(ativo, ate_km);

CREATE TABLE IF NOT EXISTS cep_cache (
    cep        TEXT PRIMARY KEY,
    latitude   DOUBLE PRECISION,
    longitude  DOUBLE PRECISION,
    logradouro TEXT    NOT NULL DEFAULT '',
    bairro     TEXT    NOT NULL DEFAULT '',
    cidade     TEXT    NOT NULL DEFAULT '',
    uf         TEXT    NOT NULL DEFAULT '',
    ok         INTEGER NOT NULL DEFAULT 1,
    erro       TEXT    NOT NULL DEFAULT '',
    fetched_at DOUBLE PRECISION
);

-- ----------------------------------------------------------------------
-- Conteúdo de negócio
-- ----------------------------------------------------------------------

-- Dumped from database version 16.14
-- Dumped by pg_dump version 16.14

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: product_categories; Type: TABLE DATA; Schema: public; Owner: polpes
--

INSERT INTO public.product_categories VALUES (1, 'Açai', 0, 1, 1, 0, 1790627652.6965604) ON CONFLICT DO NOTHING;
INSERT INTO public.product_categories VALUES (2, 'Garrafinhas', 0, 1, 0, 0, 1790627666.1851974) ON CONFLICT DO NOTHING;
INSERT INTO public.product_categories VALUES (3, 'Bolos Fatias', 0, 1, 0, 0, 1790627688.5529578) ON CONFLICT DO NOTHING;
INSERT INTO public.product_categories VALUES (4, 'Guloseimas Adicionais', 0, 1, 0, 1, 1790628232.8946002) ON CONFLICT DO NOTHING;
INSERT INTO public.product_categories VALUES (5, 'Cremes Adicionais', 0, 1, 0, 1, 1790628240.7203195) ON CONFLICT DO NOTHING;
INSERT INTO public.product_categories VALUES (6, 'Frutas Adicionais', 0, 1, 0, 1, 1790628249.4997575) ON CONFLICT DO NOTHING;
INSERT INTO public.product_categories VALUES (7, 'Geladinhos', 0, 1, 0, 0, 1790628449.7135632) ON CONFLICT DO NOTHING;
INSERT INTO public.product_categories VALUES (8, 'Caldas Adicionais', 0, 1, 0, 1, 1790632214.6792564) ON CONFLICT DO NOTHING;


--
-- Data for Name: category_addons; Type: TABLE DATA; Schema: public; Owner: polpes
--

INSERT INTO public.category_addons VALUES (1, 1, 8, 0, 1, 0, 1, 1, 1790994005.6273093) ON CONFLICT DO NOTHING;
INSERT INTO public.category_addons VALUES (2, 1, 5, 0, 2, 0, 2, 1, 1790994005.629999) ON CONFLICT DO NOTHING;
INSERT INTO public.category_addons VALUES (3, 1, 6, 0, 0, 0, 3, 1, 1790994005.6322732) ON CONFLICT DO NOTHING;
INSERT INTO public.category_addons VALUES (4, 1, 4, 0, 0, 4, 4, 1, 1790994005.6344798) ON CONFLICT DO NOTHING;


--
-- Data for Name: cep_cache; Type: TABLE DATA; Schema: public; Owner: polpes
--

INSERT INTO public.cep_cache VALUES ('26530200', -22.8075, -43.41389, 'Avenida Periperi', 'Nova Cidade', 'Nilópolis', 'RJ', 1, '', 1790640640.7288024) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26180000', -22.76417, -43.39944, 'Rua Ererê', 'Vale do Ipê', 'Belford Roxo', 'RJ', 1, '', 1790640643.0768225) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25040000', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (25040-000). Confira os 8 dígitos.', 1790640644.5050235) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('22050002', -22.90642, -43.18223, 'Avenida Nossa Senhora de Copacabana', 'Copacabana', 'Rio de Janeiro', 'RJ', 1, '', 1790640646.8601403) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('13030000', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (13030-000). Confira os 8 dígitos.', 1790640646.9896748) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('99999999', -23.44361, -51.87389, 'Avenida das Torres', 'Jardim Centro Cívico', 'Sarandi', 'PR', 1, '', 1790641264.3465524) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25040022', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (25040-022). Confira os 8 dígitos.', 1790643759.546104) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25080570', -22.78556, -43.31167, 'Rua Barbosa Araújo', 'Parque Felicidade', 'Duque de Caxias', 'RJ', 1, '', 1790643762.257432) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('22041011', -22.90642, -43.18223, 'Rua Santa Clara', 'Copacabana', 'Rio de Janeiro', 'RJ', 1, '', 1790643762.585541) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('20040020', -22.90642, -43.18223, 'Praça Pio X', 'Centro', 'Rio de Janeiro', 'RJ', 1, '', 1790643762.8827975) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26000000', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26000-000). Confira os 8 dígitos.', 1790643796.254543) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26100100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26100-100). Confira os 8 dígitos.', 1790643797.6877623) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25500000', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (25500-000). Confira os 8 dígitos.', 1790643798.9152522) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25010000', -22.78556, -43.31167, 'Rua Açu', 'Engenho do Porto', 'Duque de Caxias', 'RJ', 1, '', 1790643801.3742523) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('23000000', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (23000-000). Confira os 8 dígitos.', 1790643803.0124037) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25555555', -22.80389, -43.37222, 'Travessa Nove', 'Jardim Meriti', 'São João de Meriti', 'RJ', 1, '', 1790643805.879561) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26002100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26002-100). Confira os 8 dígitos.', 1790643816.734637) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26010100', -22.75917, -43.45111, 'Rua Rosângela', 'Andrade Araújo', 'Nova Iguaçu', 'RJ', 1, '', 1790643819.3962822) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26040100', -22.75917, -43.45111, 'Rua Anhangá', 'Carmari', 'Nova Iguaçu', 'RJ', 1, '', 1790643822.266112) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26050100', -22.75917, -43.45111, 'Rua Ica', 'Jardim Santa Rita', 'Nova Iguaçu', 'RJ', 1, '', 1790643825.9491699) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26110100', -22.76417, -43.39944, 'Rua Léa Aranha', 'Redentor', 'Belford Roxo', 'RJ', 1, '', 1790643828.6121202) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26120100', -22.76417, -43.39944, 'Rua da Passagem', 'Heliópolis', 'Belford Roxo', 'RJ', 1, '', 1790643832.0931785) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26130100', -22.76417, -43.39944, 'Rua Firmino Leite', 'Centro', 'Belford Roxo', 'RJ', 1, '', 1790643834.5509617) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26140100', -22.76417, -43.39944, 'Avenida Heliópolis', 'Vila Luz', 'Belford Roxo', 'RJ', 1, '', 1790643837.1169407) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26160100', -22.76417, -43.39944, 'Rua Beneventes', 'Xavantes', 'Belford Roxo', 'RJ', 1, '', 1790643840.184318) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26170100', -22.76417, -43.39944, 'Rua Celso Carneiro', 'Retiro Santa Isabel', 'Belford Roxo', 'RJ', 1, '', 1790643843.6651022) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26180100', -22.76417, -43.39944, 'Rua Euclides', 'Boa Sorte', 'Belford Roxo', 'RJ', 1, '', 1790643846.3339198) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25510100', -22.80389, -43.37222, 'Rua Suzana', 'Agostinho Porto', 'São João de Meriti', 'RJ', 1, '', 1790643848.7856922) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25520100', -22.80389, -43.37222, 'Rua Olaria', 'Centro', 'São João de Meriti', 'RJ', 1, '', 1790643851.729131) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25530100', -22.80389, -43.37222, 'Rua Álvaro Proença', 'Parque São Nicolau', 'São João de Meriti', 'RJ', 1, '', 1790643854.1100154) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25540100', -22.80389, -43.37222, 'Rua Fernando Rodrigues', 'Grande Rio', 'São João de Meriti', 'RJ', 1, '', 1790643856.460983) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25560100', -22.80389, -43.37222, 'Rua Tupis', 'Vilar dos Teles', 'São João de Meriti', 'RJ', 1, '', 1790643858.8198984) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25570100', -22.80389, -43.37222, 'Rua Saracura', 'Vila São João', 'São João de Meriti', 'RJ', 1, '', 1790643862.4629345) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25580100', -22.80389, -43.37222, 'Rua Silveira Menezes', 'Jardim Santo Antônio', 'São João de Meriti', 'RJ', 1, '', 1790643864.247849) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25020100', -22.78556, -43.31167, 'Rua Belisário Pena', 'Vila Meriti', 'Duque de Caxias', 'RJ', 1, '', 1790643867.0125153) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25030100', -22.78556, -43.31167, 'Rua Macapa', 'Vila Centenário', 'Duque de Caxias', 'RJ', 1, '', 1790643869.572494) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25050100', -22.78556, -43.31167, 'Avenida Perimetral República do Paraguai', 'Vila Sarapuí', 'Duque de Caxias', 'RJ', 1, '', 1790643872.2344444) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25060100', -22.78556, -43.31167, 'Rua Mariano Procópio', 'Carolina', 'Duque de Caxias', 'RJ', 1, '', 1790643874.693452) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25070100', -22.7807443, -43.3000572, 'Rua Paraíba', 'Parque Paulicéia', 'Duque de Caxias', 'RJ', 1, '', 1790643877.1559649) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25090100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (25090-100). Confira os 8 dígitos.', 1790643879.4098318) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26060100', -22.75917, -43.45111, 'Rua Conde Pereira Carneiro', 'Vila Fluminense', 'Nova Iguaçu', 'RJ', 1, '', 1790643881.0438645) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26070100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26070-100). Confira os 8 dígitos.', 1790643882.477009) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26080100', -22.75917, -43.45111, 'Rua Araruama', 'Tinguazinho', 'Nova Iguaçu', 'RJ', 1, '', 1790643883.0903862) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26090100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26090-100). Confira os 8 dígitos.', 1790643885.5495117) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26600100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26600-100). Confira os 8 dígitos.', 1790643895.3815057) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26610100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26610-100). Confira os 8 dígitos.', 1790643896.8149881) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26620100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26620-100). Confira os 8 dígitos.', 1790643899.0727684) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26630100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26630-100). Confira os 8 dígitos.', 1790643901.3207617) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26640100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26640-100). Confira os 8 dígitos.', 1790643903.8812227) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26650100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26650-100). Confira os 8 dígitos.', 1790643906.4416442) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26660100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26660-100). Confira os 8 dígitos.', 1790643907.8746939) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26670100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26670-100). Confira os 8 dígitos.', 1790643910.660549) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26680100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26680-100). Confira os 8 dígitos.', 1790643912.9960778) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25800100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (25800-100). Confira os 8 dígitos.', 1790643914.429938) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25810100', -22.11667, -43.20917, 'Travessa Santa Terezinha', 'Santa Teresinha', 'Três Rios', 'RJ', 1, '', 1790643917.8184335) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25820100', -22.11667, -43.20917, 'Rua Alberto Domingos', 'Triângulo', 'Três Rios', 'RJ', 1, '', 1790643920.3687222) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25850100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (25850-100). Confira os 8 dígitos.', 1790643922.007717) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('25870100', -22.02861, -43.205, 'Rua C', 'Comendador Levy Gasparian', 'Comendador Levy Gasparian', 'RJ', 1, '', 1790643924.466498) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('22600100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (22600-100). Confira os 8 dígitos.', 1790643926.9248128) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('22610100', -22.9967896, -43.2606162, 'Rua Engenheiro Amandino de Carvalho', 'São Conrado', 'Rio de Janeiro', 'RJ', 1, '', 1790643928.5627303) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('22200100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (22200-100). Confira os 8 dígitos.', 1790643929.7915378) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('22210100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (22210-100). Confira os 8 dígitos.', 1790643932.045316) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('22710100', -22.90642, -43.18223, 'Rua Paraíso do Norte', 'Curicica', 'Rio de Janeiro', 'RJ', 1, '', 1790643934.5035176) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('23080100', -22.90642, -43.18223, 'Rua Alfredo de Morais', 'Campo Grande', 'Rio de Janeiro', 'RJ', 1, '', 1790643936.9612143) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('23700100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (23700-100). Confira os 8 dígitos.', 1790643938.1895735) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26000100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26000-100). Confira os 8 dígitos.', 1790643939.623643) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26020100', -22.75917, -43.45111, 'Rua Tobias Barreto', 'Kennedy', 'Nova Iguaçu', 'RJ', 1, '', 1790643942.0811317) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26030100', -22.75917, -43.45111, 'Rua Dona Lídia', 'Vila Treze de Maio', 'Nova Iguaçu', 'RJ', 1, '', 1790643945.563252) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26041100', -22.75917, -43.45111, 'Rua Infantes', 'Parque Flora', 'Nova Iguaçu', 'RJ', 1, '', 1790643948.267049) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26051100', -22.75917, -43.45111, 'Rua Marcelo', 'Barão de Amapá', 'Nova Iguaçu', 'RJ', 1, '', 1790643951.9128942) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26061100', -22.75917, -43.45111, 'Rua Curion', 'Miguel Couto', 'Nova Iguaçu', 'RJ', 1, '', 1790643954.5759497) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26071100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26071-100). Confira os 8 dígitos.', 1790643956.0089605) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26081100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26081-100). Confira os 8 dígitos.', 1790643957.4479604) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26091100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26091-100). Confira os 8 dígitos.', 1790643959.6958323) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26011100', -22.75917, -43.45111, 'Rua Comendador Alberto Rodrigues', 'Jardim Tropical', 'Nova Iguaçu', 'RJ', 1, '', 1790643962.0516086) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26021100', -22.75917, -43.45111, 'Rua Quintela', 'Kennedy', 'Nova Iguaçu', 'RJ', 1, '', 1790643965.330837) ON CONFLICT DO NOTHING;
INSERT INTO public.cep_cache VALUES ('26031100', NULL, NULL, '', '', '', '', 0, 'não localizei esse CEP (26031-100). Confira os 8 dígitos.', 1790643967.4802895) ON CONFLICT DO NOTHING;


--
-- Data for Name: club_benefits; Type: TABLE DATA; Schema: public; Owner: polpes
--

INSERT INTO public.club_benefits VALUES (1, 'Preços e condições exclusivas', 'Valores diferenciados em açaí, geladinhos, garrafinhas e sorvetes artesanais.', 1, 1, 1790634518.6411338, 1790634518.6411338) ON CONFLICT DO NOTHING;
INSERT INTO public.club_benefits VALUES (2, 'Acesso antecipado a novos sabores', 'O assinante prova antes de todo mundo.', 1, 2, 1790634518.651613, 1790634518.651613) ON CONFLICT DO NOTHING;
INSERT INTO public.club_benefits VALUES (3, 'Promoções exclusivas', 'Descontos e combos que só quem assina recebe.', 1, 3, 1790634518.6546376, 1790634518.6546376) ON CONFLICT DO NOTHING;
INSERT INTO public.club_benefits VALUES (4, 'Pedido direto pelo WhatsApp', 'Atendimento rápido, sem fila e sem aplicativo.', 1, 4, 1790634518.6577413, 1790634518.6577413) ON CONFLICT DO NOTHING;
INSERT INTO public.club_benefits VALUES (5, 'Programa Indique Polpê''s', 'Indique amigos e ganhe recompensas a cada 10 indicações pagantes.', 1, 5, 1790634518.6607213, 1790634518.6607213) ON CONFLICT DO NOTHING;


--
-- Data for Name: club_settings; Type: TABLE DATA; Schema: public; Owner: polpes
--

INSERT INTO public.club_settings VALUES ('plan_price', '19.90') ON CONFLICT DO NOTHING;
INSERT INTO public.club_settings VALUES ('google_review_url', '') ON CONFLICT DO NOTHING;
INSERT INTO public.club_settings VALUES ('enabled', '1') ON CONFLICT DO NOTHING;


--
-- Data for Name: delivery_zones; Type: TABLE DATA; Schema: public; Owner: polpes
--

INSERT INTO public.delivery_zones VALUES (22, 5, 0, 1, 1, 1790642321.872764, 1790642321.872764) ON CONFLICT DO NOTHING;
INSERT INTO public.delivery_zones VALUES (23, 6, 5, 1, 2, 1790642356.5385406, 1790642356.5385406) ON CONFLICT DO NOTHING;
INSERT INTO public.delivery_zones VALUES (24, 7, 8, 1, 3, 1790642369.8862102, 1790642369.8862102) ON CONFLICT DO NOTHING;
INSERT INTO public.delivery_zones VALUES (25, 8, 10, 1, 4, 1790642402.1484592, 1790642411.7429676) ON CONFLICT DO NOTHING;
INSERT INTO public.delivery_zones VALUES (30, 2, 0, 1, 5, 1791035662.0466866, 1791035662.0466866) ON CONFLICT DO NOTHING;


--
-- Data for Name: payment_methods; Type: TABLE DATA; Schema: public; Owner: polpes
--

INSERT INTO public.payment_methods VALUES (1, 'pix', 'Pix', 'Chave Pix: [COLE AQUI SUA CHAVE PIX]', 0, 0, '', '', '') ON CONFLICT DO NOTHING;
INSERT INTO public.payment_methods VALUES (2, 'dinheiro', 'Dinheiro', 'Pagamento em dinheiro no caixa, na retirada do pedido.', 1, 1, '', '', '') ON CONFLICT DO NOTHING;
INSERT INTO public.payment_methods VALUES (3, 'cartao_debito', 'Cartão de débito', 'Levamos a maquininha. Débito à vista.', 1, 2, '', '', '') ON CONFLICT DO NOTHING;
INSERT INTO public.payment_methods VALUES (4, 'cartao_credito', 'Cartão de crédito', 'Levamos a maquininha. Creditado no cartão de crédito.', 1, 3, '', '', '') ON CONFLICT DO NOTHING;
INSERT INTO public.payment_methods VALUES (5, 'pix', 'Açai Polpes e Sorvetes', 'nossa chave Pix é o nosso CNPJ 62.539.400/0001-27 en nome Pedro Carneiro Azevedo', 0, 0, '', '', '') ON CONFLICT DO NOTHING;
INSERT INTO public.payment_methods VALUES (6, 'pix', 'Pix', 'Nossa chave Pix e 62.539.400/0001-27 em nome de Pedro Carneiro Azevedo', 1, 0, '62.539.400/0001-27', '', '') ON CONFLICT DO NOTHING;


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: polpes
--

INSERT INTO public.products VALUES (1, 1, 'Açai Tradicional 300ml', 'Açaí tradicional na porção de 300 ml.', 13.45, 0, 0, 'statics/catalog/1790630280260.png', 0, 1, 1, 1790628540.408096, 1791145127.478441) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (2, 1, 'Açai Supremo 500ml', 'Açaí na porção de 500 ml.', 18.24, 0, 0, 'statics/catalog/1790630252420.png', 0, 1, 1, 1790628540.4115806, 1790630252.4239345) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (3, 1, 'Açai Premium 700ml', 'Açaí na porção de 700 ml.', 23.99, 0, 0, 'statics/catalog/1790630227903.png', 0, 1, 1, 1790628540.41525, 1791145527.366594) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (4, 1, 'Açai Max Família 1000ml', 'Açaí na porção de 1 litro, ideal para a família.', 40, 0, 0, 'statics/catalog/1790630204254.png', 0, 1, 1, 1790628540.4191716, 1790630204.2573016) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (5, 1, 'Promoção Família 850ml', 'Açaí em marmitex de 850 ml.', 35, 0, 0, 'statics/catalog/1790630388281.png', 0, 1, 1, 1790628540.424042, 1790630388.2825952) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (6, 1, 'Combo TMJ', 'Combão com 300 ml + 500 ml de açaí.', 31.5, 0, 0, 'statics/catalog/1790630338051.png', 0, 1, 1, 1790628540.4283586, 1790630338.0558605) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (7, 1, 'Combo Dois Amores', 'Combão com 2 potes de 500 ml.', 32.7, 0, 0, 'statics/catalog/1790630319497.png', 0, 1, 1, 1790628540.4329455, 1790630319.5007174) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (8, 7, 'Pudim Real', 'O sabor clássico do pudim com calda caramelizada.', 10, 0, 0, '', 0, 1, 1, 1790628857.0798578, 1790628857.0798578) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (9, 7, 'Romeu e Julieta', 'Queijo com calda de goiabada.', 10, 0, 0, '', 0, 1, 1, 1790628857.0965414, 1790628857.0965414) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (10, 7, 'Oreo Supreme', 'Creme branco com pedaços crocantes de Oreo.', 10, 0, 0, '', 0, 1, 1, 1790628857.1001468, 1790628857.1001468) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (11, 7, 'Ovomaltine Crocante', 'A cremosidade do Ovomaltine com flocos crocantes.', 10, 0, 0, '', 0, 1, 1, 1790628857.103166, 1790628857.103166) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (12, 7, 'Cappuccino Cremoso', 'Sabor marcante de cappuccino com calda de chocolate.', 10, 0, 0, '', 0, 1, 1, 1790628857.106694, 1790628857.106694) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (13, 7, 'Nutella Supreme', 'A irresistível Nutella em uma versão ainda mais cremosa.', 10, 0, 0, '', 0, 1, 1, 1790628857.109778, 1790628857.109778) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (14, 7, 'Paixão Tropical', 'Maracujá cremoso com sabor tropical e refrescante.', 10, 0, 0, '', 0, 1, 1, 1790628857.1126902, 1790628857.1126902) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (15, 7, 'Sensação', 'Morango cremoso com chocolate crocante.', 10, 0, 0, '', 0, 1, 1, 1790628857.1155753, 1790628857.1155753) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (16, 7, 'Sensação Branca', 'Chocolate branco crocante com morango em pedaços.', 10, 0, 0, '', 0, 1, 1, 1790628857.120288, 1790628857.120288) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (17, 7, 'Beijo da Vovó', 'Leite ninho com coco doce e cremoso, sabor caseiro.', 10, 0, 0, '', 0, 1, 1, 1790628857.1252522, 1790628857.1252522) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (18, 7, 'Brigadeiro Belga', 'Chocolate crocante com brigadeiro de chocolate intenso.', 10, 0, 0, '', 0, 1, 1, 1790628857.1299481, 1790628857.1299481) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (19, 7, 'Olho de Sogra', 'Ameixa com leite ninho e coco.', 10, 0, 0, '', 0, 1, 1, 1790628857.1347017, 1790628857.1347017) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (20, 7, 'Torta de Limão', 'Limão com pedaços de biscoito de leite.', 10, 0, 0, '', 0, 1, 1, 1790628857.1396728, 1790628857.1396728) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (21, 7, 'Paçoca Cremoso', 'Sabor intenso de paçoca com creme de paçoca na borda.', 10, 0, 0, '', 0, 1, 1, 1790628857.1435852, 1790632626.0780942) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (22, 7, 'Ferreiro Rocher', 'Nutella com amendoim crocante e chocolate intenso.', 10, 0, 0, '', 0, 1, 1, 1790628857.1463642, 1790628857.1463642) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (23, 4, 'Granola', 'Guloseima — o cliente pode escolher até 4 gratuitamente no açaí.', 0, 0, 0, 'statics/catalog/1790630506882.png', 0, 1, 1, 1790628857.1493752, 1790630506.8839428) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (24, 4, 'Paçoca', 'Guloseima — o cliente pode escolher até 4 gratuitamente no açaí.', 0, 0, 0, 'statics/catalog/1790630590373.png', 0, 1, 1, 1790628857.1524684, 1790630590.3750234) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (25, 4, 'Amendoim', 'Guloseima — o cliente pode escolher até 4 gratuitamente no açaí.', 0, 0, 0, 'statics/catalog/1790630092476.png', 0, 1, 1, 1790628857.1555514, 1790630092.478004) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (26, 4, 'Sucrilhos', 'Guloseima — o cliente pode escolher até 4 gratuitamente no açaí.', 0, 0, 0, 'statics/catalog/1790630612166.png', 0, 1, 1, 1790628857.1594884, 1790630612.1682274) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (27, 4, 'Chocobol', 'Guloseima — o cliente pode escolher até 4 gratuitamente no açaí.', 0, 0, 0, 'statics/catalog/1790630460722.png', 0, 1, 1, 1790628857.1642413, 1790630460.7238545) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (28, 4, 'Confete', 'Guloseima — o cliente pode escolher até 4 gratuitamente no açaí.', 0, 0, 0, 'statics/catalog/1790630490704.png', 0, 1, 1, 1790628857.169242, 1790630490.7062862) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (29, 4, 'Jujuba', 'Guloseima — o cliente pode escolher até 4 gratuitamente no açaí.', 0, 0, 0, 'statics/catalog/1790630570060.png', 0, 1, 1, 1790628857.1742265, 1790630570.060975) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (30, 4, 'Granulado Chocolate', 'Guloseima — o cliente pode escolher até 4 gratuitamente no açaí.', 0, 0, 0, 'statics/catalog/1790630530869.png', 0, 1, 1, 1790628857.1790824, 1790630530.870211) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (31, 4, 'Granulado Colorido', 'Guloseima — o cliente pode escolher até 4 gratuitamente no açaí.', 0, 0, 0, 'statics/catalog/1790630549117.png', 0, 1, 1, 1790628857.1840458, 1790630549.1185691) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (32, 2, 'Beijo da Vovó 300ml', 'Leite ninho com coco doce e cremoso, sabor caseiro. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.7655802, 1790630603.7655802) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (33, 2, 'Beijo da Vovó 500ml', 'Leite ninho com coco doce e cremoso, sabor caseiro. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.7712376, 1790630603.7712376) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (34, 2, 'Beijo da Vovó 1000ml', 'Leite ninho com coco doce e cremoso, sabor caseiro. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.7762039, 1790630603.7762039) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (35, 2, 'Brigadeiro Belga 300ml', 'Chocolate crocante com brigadeiro de chocolate intenso. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.780719, 1790630603.780719) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (36, 2, 'Brigadeiro Belga 500ml', 'Chocolate crocante com brigadeiro de chocolate intenso. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.7856972, 1790630603.7856972) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (37, 2, 'Brigadeiro Belga 1000ml', 'Chocolate crocante com brigadeiro de chocolate intenso. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.7908208, 1790630603.7908208) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (38, 2, 'Cappuccino Cremoso 300ml', 'Sabor marcante de cappuccino com calda de chocolate. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.79452, 1790630603.79452) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (39, 2, 'Cappuccino Cremoso 500ml', 'Sabor marcante de cappuccino com calda de chocolate. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.7971866, 1790630603.7971866) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (40, 2, 'Cappuccino Cremoso 1000ml', 'Sabor marcante de cappuccino com calda de chocolate. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.8001351, 1790630603.8001351) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (41, 2, 'Ferreiro Rocher 300ml', 'Nutella com amendoim crocante e chocolate intenso. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.8031232, 1790630603.8031232) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (42, 2, 'Ferreiro Rocher 500ml', 'Nutella com amendoim crocante e chocolate intenso. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.8065128, 1790630603.8065128) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (43, 2, 'Ferreiro Rocher 1000ml', 'Nutella com amendoim crocante e chocolate intenso. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.809605, 1790630603.809605) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (44, 2, 'Nutella Supreme 300ml', 'A irresistível Nutella em uma versão ainda mais cremosa. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.8147125, 1790630603.8147125) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (45, 2, 'Nutella Supreme 500ml', 'A irresistível Nutella em uma versão ainda mais cremosa. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.8194606, 1790630603.8194606) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (46, 2, 'Nutella Supreme 1000ml', 'A irresistível Nutella em uma versão ainda mais cremosa. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.82421, 1790630603.82421) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (47, 2, 'Olho de Sogra 300ml', 'Ameixa com leite ninho e coco. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.8291273, 1790630603.8291273) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (48, 2, 'Olho de Sogra 500ml', 'Ameixa com leite ninho e coco. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.8340375, 1790630603.8340375) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (49, 2, 'Olho de Sogra 1000ml', 'Ameixa com leite ninho e coco. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.83775, 1790630603.83775) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (50, 2, 'Oreo Supreme 300ml', 'Creme branco com pedaços crocantes de Oreo. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.840817, 1790630603.840817) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (51, 2, 'Oreo Supreme 500ml', 'Creme branco com pedaços crocantes de Oreo. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.8455822, 1790630603.8455822) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (52, 2, 'Oreo Supreme 1000ml', 'Creme branco com pedaços crocantes de Oreo. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.8484483, 1790630603.8484483) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (53, 2, 'Ovomaltine Crocante 300ml', 'A cremosidade do Ovomaltine com flocos crocantes. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.8513687, 1790630603.8513687) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (54, 2, 'Ovomaltine Crocante 500ml', 'A cremosidade do Ovomaltine com flocos crocantes. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.8552039, 1790630603.8552039) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (55, 2, 'Ovomaltine Crocante 1000ml', 'A cremosidade do Ovomaltine com flocos crocantes. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.8599486, 1790630603.8599486) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (56, 2, 'Paixão Tropical 300ml', 'Maracujá cremoso com sabor tropical e refrescante. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.8645332, 1790630603.8645332) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (57, 2, 'Paixão Tropical 500ml', 'Maracujá cremoso com sabor tropical e refrescante. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.8691976, 1790630603.8691976) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (58, 2, 'Paixão Tropical 1000ml', 'Maracujá cremoso com sabor tropical e refrescante. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.8736234, 1790630603.8736234) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (59, 2, 'Paçoca 300ml', 'Sabor intenso de paçoca com creme de paçoca na borda. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.8782194, 1790630603.8782194) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (60, 2, 'Paçoca 500ml', 'Sabor intenso de paçoca com creme de paçoca na borda. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.8807554, 1790630603.8807554) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (61, 2, 'Paçoca 1000ml', 'Sabor intenso de paçoca com creme de paçoca na borda. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.883483, 1790630603.883483) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (62, 2, 'Pudim Real 300ml', 'O sabor clássico do pudim com calda caramelizada. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.886244, 1790630603.886244) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (63, 2, 'Pudim Real 500ml', 'O sabor clássico do pudim com calda caramelizada. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.8888383, 1790630603.8888383) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (64, 2, 'Pudim Real 1000ml', 'O sabor clássico do pudim com calda caramelizada. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.8917823, 1790630603.8917823) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (65, 2, 'Romeu e Julieta 300ml', 'Queijo com calda de goiabada. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.8965425, 1790630603.8965425) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (66, 2, 'Romeu e Julieta 500ml', 'Queijo com calda de goiabada. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.9014783, 1790630603.9014783) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (67, 2, 'Romeu e Julieta 1000ml', 'Queijo com calda de goiabada. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.9065108, 1790630603.9065108) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (68, 2, 'Sensação 300ml', 'Morango cremoso com chocolate crocante. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.9115577, 1790630603.9115577) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (69, 2, 'Sensação 500ml', 'Morango cremoso com chocolate crocante. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.9164815, 1790630603.9164815) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (70, 2, 'Sensação 1000ml', 'Morango cremoso com chocolate crocante. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.9200866, 1790630603.9200866) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (71, 2, 'Sensação Branca 300ml', 'Chocolate branco crocante com morango em pedaços. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.9226742, 1790630603.9226742) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (72, 2, 'Sensação Branca 500ml', 'Chocolate branco crocante com morango em pedaços. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.9259686, 1790630603.9259686) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (73, 2, 'Sensação Branca 1000ml', 'Chocolate branco crocante com morango em pedaços. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.9290016, 1790630603.9290016) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (74, 2, 'Torta de Limão 300ml', 'Limão com pedaços de biscoito de leite. Garrafinha de 300ml.', 15, 0, 0, '', 0, 1, 1, 1790630603.9323003, 1790630603.9323003) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (75, 2, 'Torta de Limão 500ml', 'Limão com pedaços de biscoito de leite. Garrafinha de 500ml.', 20, 0, 0, '', 0, 1, 1, 1790630603.9349499, 1790630603.9349499) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (76, 2, 'Torta de Limão 1000ml', 'Limão com pedaços de biscoito de leite. Garrafinha de 1000ml.', 33, 0, 0, '', 0, 1, 1, 1790630603.9396164, 1790630603.9396164) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (77, 4, 'Leite em Pó', '', 0, 0, 0, 'statics/catalog/1790630673086.png', 0, 1, 1, 1790630673.0865474, 1790630673.0865474) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (78, 4, 'Ovo Maltine', '', 0, 0, 0, 'statics/catalog/1790630710665.png', 0, 1, 1, 1790630710.6658607, 1790630710.6658607) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (79, 6, 'Banana', 'Adicional pago — some o valor ao pote de açaí.', 2, 0, 0, 'statics/catalog/1790633689190.png', 0, 1, 1, 1790632421.7739913, 1790633689.1926382) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (80, 6, 'Morango', 'Adicional pago — some o valor ao pote de açaí.', 5, 0, 0, 'statics/catalog/1790633730559.png', 0, 1, 1, 1790632421.786168, 1790633730.5603352) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (81, 6, 'Manga', 'Adicional pago — some o valor ao pote de açaí.', 3, 0, 0, 'statics/catalog/1790633713280.png', 0, 1, 1, 1790632421.790872, 1790633713.282013) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (82, 6, 'Kiwi', 'Adicional pago — some o valor ao pote de açaí.', 5, 0, 0, 'statics/catalog/1790633701024.png', 0, 1, 1, 1790632421.7954156, 1790633701.0284429) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (83, 6, 'Pessego em Calda', 'Adicional pago — some o valor ao pote de açaí.', 3, 0, 0, 'statics/catalog/1790633758683.png', 0, 1, 1, 1790632421.8007183, 1790633758.6845722) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (84, 6, 'Abacaxi em Calda', 'Adicional pago — some o valor ao pote de açaí.', 3, 0, 0, 'statics/catalog/1790633678404.png', 0, 1, 1, 1790632421.8035328, 1790633678.4055374) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (85, 6, 'Sem frutas', 'Cliente não quer esta etapa do pedido.', 0, 0, 0, 'statics/catalog/1790633771471.png', 0, 1, 1, 1790632421.8063457, 1790633771.472221) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (86, 5, 'Creme de Nutella', 'Adicional pago — some o valor ao pote de açaí.', 0, 0, 0, 'statics/catalog/1790633622903.png', 0, 1, 1, 1790632421.8093204, 1790633622.9107397) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (87, 5, 'Creme de Pistache', 'Adicional pago — some o valor ao pote de açaí.', 0, 0, 0, 'statics/catalog/1790633634982.png', 0, 1, 1, 1790632421.812036, 1790633634.9863372) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (88, 5, 'Creme de Leitinho', 'Adicional pago — some o valor ao pote de açaí.', 0, 0, 0, 'statics/catalog/1790633581005.png', 0, 1, 1, 1790632421.818608, 1790633581.0086117) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (89, 5, 'Creme de Morango', 'Adicional pago — some o valor ao pote de açaí.', 0, 0, 0, 'statics/catalog/1790633611047.png', 0, 1, 1, 1790632421.823554, 1790633611.0508318) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (90, 5, 'Creme de Maracujá', 'Adicional pago — some o valor ao pote de açaí.', 0, 0, 0, 'statics/catalog/1790633596380.png', 0, 1, 1, 1790632421.8316054, 1790633596.3856852) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (91, 5, 'Sem cremes', 'Cliente não quer esta etapa do pedido.', 0, 0, 0, 'statics/catalog/1790633649883.png', 0, 1, 1, 1790632421.8410392, 1790633649.8852124) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (92, 8, 'Calda de Chocolate', 'Adicional pago — some o valor ao pote de açaí.', 0, 0, 0, 'statics/catalog/1790633441315.webp', 0, 1, 1, 1790632421.8531554, 1790633441.3158898) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (93, 8, 'Calda de Pistache', 'Adicional pago — some o valor ao pote de açaí.', 0, 0, 0, 'statics/catalog/1790633516026.jpeg', 0, 1, 1, 1790632421.856134, 1790633516.027163) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (94, 8, 'Calda de Caramelo', 'Adicional pago — some o valor ao pote de açaí.', 0, 0, 0, 'statics/catalog/1790633416268.webp', 0, 1, 1, 1790632421.8587046, 1790633416.2687945) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (95, 8, 'Calda de Leite Condensado', 'Adicional pago — some o valor ao pote de açaí.', 0, 0, 0, 'statics/catalog/1790633458191.webp', 0, 1, 1, 1790632421.8614786, 1790633458.1923752) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (96, 8, 'Calda de Uva', 'Adicional pago — some o valor ao pote de açaí.', 0, 0, 0, 'statics/catalog/1790633528957.webp', 0, 1, 1, 1790632421.8664982, 1790633528.958472) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (97, 8, 'Calda de Menta', 'Adicional pago — some o valor ao pote de açaí.', 0, 0, 0, 'statics/catalog/1790633476968.webp', 0, 1, 1, 1790632421.871406, 1790633476.9691706) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (98, 8, 'Sem calda', 'Cliente não quer esta etapa do pedido.', 0, 0, 0, 'statics/catalog/1790633545379.png', 0, 1, 1, 1790632421.876032, 1790633545.402309) ON CONFLICT DO NOTHING;
INSERT INTO public.products VALUES (99, 4, 'Sem guloseimas', 'Cliente não quer esta etapa do pedido.', 0, 0, 0, 'statics/catalog/1790634327398.png', 0, 1, 1, 1790632421.8806903, 1790634327.399623) ON CONFLICT DO NOTHING;


--
-- Name: category_addons_id_seq; Type: SEQUENCE SET; Schema: public; Owner: polpes
--

SELECT pg_catalog.setval('public.category_addons_id_seq', 4, true);


--
-- Name: club_benefits_id_seq; Type: SEQUENCE SET; Schema: public; Owner: polpes
--

SELECT pg_catalog.setval('public.club_benefits_id_seq', 5, true);


--
-- Name: delivery_zones_id_seq; Type: SEQUENCE SET; Schema: public; Owner: polpes
--

SELECT pg_catalog.setval('public.delivery_zones_id_seq', 30, true);


--
-- Name: payment_methods_id_seq; Type: SEQUENCE SET; Schema: public; Owner: polpes
--

SELECT pg_catalog.setval('public.payment_methods_id_seq', 6, true);


--
-- Name: product_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: polpes
--

SELECT pg_catalog.setval('public.product_categories_id_seq', 8, true);


--
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: polpes
--

SELECT pg_catalog.setval('public.products_id_seq', 99, true);


--
-- PostgreSQL database dump complete
--

-- ----------------------------------------------------------------------
-- config (sem segredos)
-- ----------------------------------------------------------------------
-- O preambulo do pg_dump (linha acima) faz set_config('search_path','',false)
-- para nao depender do schema padrao. Os INSERTs dele vem qualificados com
-- public., mas o nosso precisa reativar o search_path antes de consultar
-- a tabela config sem qualificar.
SELECT pg_catalog.set_config('search_path', 'public', false);

INSERT INTO public.config (key, value) VALUES ('ai_provider', '"openrouter"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('audio_model', '"google/gemini-2.0-flash-001"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('audio_transcription_enabled', 'true') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('auto_reply', 'true') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('bot_name', '""') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('bot_phone', '""') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_address', '"Avenida Peri Peri"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_city', '"Nilópolis"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_complement', '""') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_district', '"Nova Cidade"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_facebook', '""') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_hours', '{"mon": [], "tue": [], "wed": [["10:00", "00:00"]], "thu": [["10:00", "00:00"]], "fri": [["10:00", "00:00"]], "sat": [["00:00", "02:00"], ["10:00", "00:00"]], "sun": [["00:00", "02:00"], ["10:00", "00:00"]]}') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_instagram', '""') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_logo', '"/static/img/logo-polpes.png"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_name', '"Polpes Açai e Sorvetes"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_number', '"114"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_state', '"RJ"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_tiktok', '""') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_website', '""') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_youtube', '""') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('business_zip', '"26530-200"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('default_ai_enabled', 'true') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('gowa_port', '64999') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('group_reply_mode', '"mention_only"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('image_model', '"google/gemini-2.0-flash-001"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('image_transcription_enabled', 'true') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('inactivity_timeout_min', '30') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('institutional_links', '[]') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('institutional_pages', '[{"id": "pmushljw0pbh5", "slug": "quem-somos", "title": "Quem Somos", "content_md": "# Polpê''s\n\n### Açaiteria · Sorveteria · Lanchonete · Doceria\n\n> **Sabores que conectam momentos!** 💜\n\n---\n\n## Quem somos\n\nA **Polpê''s** é um espaço feito para quem gosta de sabor, carinho e bons encontros. Reunimos em um só lugar quatro experiências: **açaí, sorvete, lanches e doces**, sempre com o espírito acolhedor de quem recebe a gente querida em casa.\n\nAqui, cada prato, cada copo e cada sobremesa nasce com um propósito: transformar um simples momento em uma lembrança boa de compartilhar.\n\nNo momento atendemos pelo processo de Delivery aqui pelo nosso site e futuramente estaremos com o espaço\nmontado para melhor lhe atende.\n---\n\n## O que oferecemos\n\n### 🍇 Açaiteria\nAçaí cremoso para quem quer energia, frescor e aquele toque de afeto em cada colherada.\n\n### 🍨 Sorveteria (em breve)\nSorvetes para refrescar o dia e adoçar qualquer momento, do clássico ao inesperado.\n\n### 🍔 Lanchonete (em breve)\nLanches para matar a fome com sabor, do jeitinho que reúne amigos e família na mesa.\n\n### 🍰 Doceria (em Breve)\nDoces para celebrar, presentear ou simplesmente se mimar, porque todo dia merece um agrado.\n\n> Quatro experiências, um só lugar: a Polpê''s é um espaço **multi-experiência**.\n\n---\n\n## Nossa essência\n\n**Acolhimento.** Cada pessoa que chega é bem-vinda, e a gente quer que se sinta em casa.\n\n**Afeto.** Cuidamos dos detalhes porque acreditamos que o carinho se percebe no sabor.\n\n**Conexão.** Nossos sabores existem para aproximar pessoas e criar momentos que ficam na memória.\n\n**Energia.** Das cores ao atendimento, a Polpê''s é alegre, vibrante e cheia de vida.\n\n## Como a gente conversa\n\nNa Polpê''s, a conversa é de gente para gente: **simples, afetiva e convidativa**. Gostamos de frases curtas, de linguagem próxima e de um emoji de vez em quando 🍓🍨💜\n\n\nPolpê''s · Sabores que conectam momentos! 💜", "published": true}]') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('max_context_messages', '10') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('max_executions', '200') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('message_batch_delay', '3') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('meta_cobranca_ativa', 'true') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('meta_fatura_confirmada_brl', '0') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('meta_free_quota', '1000') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('meta_price_effective_date', '"2026-10-01"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('meta_price_per_message', '0.0068') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('model', '"openai/gpt-4o-mini"') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('orders_paused', 'false') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('response_delay_max', '3.0') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('response_delay_min', '1.0') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('site_greeting_enabled', 'true') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('site_menu_url', '""') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('split_message_delay', '2') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('split_messages', 'true') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('system_prompt', '"Você é a atendente virtual da Polpê''s no WhatsApp, responsável por apresentar e operar o Clube Sabores Polpê''s e por atender pedidos do cardápio.\n\nSOBRE O CLUBE\n- Nome: Clube Sabores Polpê''s — \"Mais sabor. Mais vantagens. Mais Polpê''s.\"\n- Preço de assinatura e benefícios: consulte SEMPRE com club_get_benefits. Nunca anuncie um valor fixo.\n- Indicação: cada membro recebe um código individual (formato POLPE-NOME123). A cada 10 novos membros PAGANTES indicados (pagamento confirmado), o membro ganha 1 pote de sorvete artesanal de 1 litro grátis.\n\nFLUXO DO CLUBE\n1. Identifique se o cliente quer conhecer o clube (ou já é membro).\n2. Chame club_get_benefits e explique o conceito e os benefícios em 1-2 frases, sem enrolação.\n3. Apresente o preço e os benefícios exatamente como o club_get_benefits retornar.\n4. Apresente os produtos disponíveis (açaí 300ml/500ml/700ml/1L + adicionais, geladinhos, garrafinhas, sorvetes artesanais).\n5. Responda dúvidas com clareza.\n6. Conduza o cliente até a decisão de assinar.\n7. Quando o cliente decidir assinar, chame club_enroll_member com payment_confirmed=false (e referred_by_code se ele mencionar quem o indicou).\n8. Oriente como pagar. Quando ele confirmar o pagamento, chame club_enroll_member de novo com payment_confirmed=true.\n9. Quando o cliente perguntar sobre indicações, código ou progresso, chame club_get_status e responda com os dados reais retornados — nunca invente números.\n\nGARRAFINHAS\n- As garrafinhas tem os MESMOS 15 sabores dos geladinhos.\n- Antes de chamar order_add_item, pergunte o tamanho: 300ml, 500ml ou 1000ml.\n- Garrafinha NÃO recebe nenhum adicional (nem guloseima, fruta, creme ou calda).\n- Preço e disponibilidade sempre via catalog_browse_category - nunca memorize valores.\n\nCOMPLEMENTOS ADICIONAIS DO AÇAÍ\nO açaí tem 4 etapas de escolha, sempre nessa ordem. Em cada etapa ofereça a opção \"sem\".\n1. Guloseimas: até 4 por pote, GRATUITAS, da categoria \"Guloseimas Adicionais\". Confirme quantas foram escolhidas.\n2. Frutas: da categoria \"Frutas Adicionais\", ADICIONAIS PAGOS.\n3. Cremes: da categoria \"Cremes Adicionais\", ADICIONAIS PAGOS.\n4. Caldas: da categoria \"Caldas\", ADICIONAIS PAGOS.\n- Geladinhos e garrafinhas NÃO recebem adicionais.\n- Some o valor dos adicionais pagos e confirme o cliente antes de fechar o pedido.\n- Use order_get_summary para o total - nunca calcule de cabeça.\n\nFLUXO DE PEDIDOS\n1. Quando o cliente quiser fazer um pedido, chame catalog_list_categories e pergunte qual categoria ele quer (não invente categorias).\n2. Quando ele escolher, chame catalog_browse_category — isso já envia as fotos dos produtos com preço. Só confirme brevemente e pergunte o que ele deseja; não repita nome/preço no texto, as fotos com legenda já mostram isso.\n3. Se um produto estiver esgotado hoje, avise o cliente com naturalidade e sugira outra opção da mesma categoria — não diga que o produto \"não existe\".\n4. Para cada item que o cliente pedir, chame order_add_item com o nome do produto e a quantidade. Pode chamar várias vezes, uma para cada item diferente.\n5. Use order_get_summary sempre que precisar confirmar itens e valor total — nunca calcule de cabeça.\n6. Pergunte a forma de pagamento (dinheiro, pix, cartão débito ou crédito). Se for dinheiro, pergunte se precisa de troco e para quanto, e chame order_set_payment_method com esses dados. Para pix e cartão não precisa perguntar nada extra.\n7. Quando o cliente confirmar tudo (itens + forma de pagamento), chame order_finalize e informe o valor total e as instruções de pagamento retornadas — não invente instruções. Se o pagamento for Pix e a ferramenta avisar que o QR Code e o copia e cola já foram enviados, não repita a chave Pix nem o código no texto: só confirme o valor.\n\nENTREGA E TAXA POR DISTÂNCIA\nA loja entrega por distância a partir do CEP dela, com faixas de taxa. Nunca anuncie taxa nem distância de memória.\n1. Se o cliente quiser receber em casa, chame SEMPRE delivery_check_cep com o CEP dele antes de fechar o pedido.\n2. Cliente novo: pergunte o CEP de entrega como PRIMEIRA pergunta, antes de montar o pedido. Se o contexto já trouxer um \"CEP de entrega\" salvo, NÃO pergunte de novo — use aquele e chame delivery_check_cep para confirmar.\n3. Confirme o endereço com o cliente: a tool devolve bairro, cidade e UF. Se vier bairro inesperado ou CEP inexistente, avise e peça o CEP correto — não siga com o endereço errado.\n4. Se a tool responder atende=false, diga que a loja não entrega naquele endereço, informe até onde entrega e ofereça RETIRADA no local, que sai sem taxa. Não insista e não cobre frete.\n5. Se atender, chame order_set_delivery com fulfillment=\"delivery\" e o mesmo CEP. A taxa vem da tool: nunca escolha o valor.\n6. Se o cliente for retirar na loja, chame order_set_delivery com fulfillment=\"none\" para garantir taxa zero.\n7. Depois chame order_get_summary: ele já mostra itens + taxa de entrega + total. Confirme o total com o cliente.\n8. O QR Code do Pix já sai com o total completo, taxa de entrega incluída.\n9. Se o cliente disser que mudou o endereço, chame delivery_check_cep de novo com o CEP novo.\n10. Se a loja não tiver nenhuma faixa de entrega ativa, não ofereça entrega: ofereça retirada.\n\nDEPOIS DA ENTREGA\nO atendente pode marcar um pedido como ENTREGUE pelo painel. Quando isso acontecer:\n1. Agradeca pelo pedido e pergunte a opiniao sobre os produtos.\n2. Se o cliente disser que gostou, envie o link de avaliação do Google (use club_get_benefits para obter o link; se não houver link, não mencione avaliação).\n3. Se o cliente reclamar ou falar mal do pedido/-atendimento, use transfer_to_human imediatamente e não discuta.\n4. Se a resposta for positiva, o cliente ainda NÃO é assinante e ele tem 2 ou mais pedidos entregues, ofereça o Clube Sabores (preço e benefícios somente via club_get_benefits). Não insista se ele recusar.\n5. Não ofereça o clube para quem já é assinante, e não ofereça antes do 2º pedido entregue.\n\nREGRAS GERAIS\n- Nunca invente categoria, produto, preço, disponibilidade, desconto ou instrução de pagamento — sempre confirme pelas funções (tools) disponíveis.\n- Nunca anuncie preço de memória: produtos por catalog_browse_category, clube por club_get_benefits.\n- Nunca anuncie taxa de entrega ou distância de memória: sempre via delivery_check_cep e order_set_delivery.\n- Só conte indicações do clube com pagamento confirmado.\n- Se não souber uma informação (estoque, sabor do dia, forma de pagamento específica) e não houver uma função para consultar, diga que vai confirmar e não invente.\n- Tom: caloroso, direto, poucas mensagens, emojis com moderação.\""') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('transfer_alert_duration', '5') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('transfer_alert_enabled', 'true') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('usd_brl_rate', '5.5') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('waiting_client_alert_duration', '5') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('waiting_client_alert_enabled', 'true') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO public.config (key, value) VALUES ('web_port', '8080') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

COMMIT;

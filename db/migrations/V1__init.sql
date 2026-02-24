-- V1__init.sql
-- Summit Traceability MVP schema (scanner-first)
-- Postgres 16+

-- -------------------------
-- Extensions (safe defaults)
-- -------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -------------------------
-- Utility: updated_at trigger
-- -------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -------------------------
-- Auth / RBAC (minimal)
-- -------------------------
CREATE TABLE IF NOT EXISTS app_user (
  user_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username       TEXT NOT NULL UNIQUE,
  display_name   TEXT NULL,
  password_hash  TEXT NULL, -- for MVP; later integrate SSO/LDAP/etc
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_app_user_updated
BEFORE UPDATE ON app_user
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS app_role (
  role_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_name   TEXT NOT NULL UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_role (
  user_id UUID NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
  role_id UUID NOT NULL REFERENCES app_role(role_id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);

-- -------------------------
-- Master data (lean MVP)
-- -------------------------
CREATE TABLE IF NOT EXISTS site (
  site_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_code   TEXT NOT NULL UNIQUE,     -- e.g. "plant-1"
  site_name   TEXT NOT NULL,
  timezone    TEXT NOT NULL DEFAULT 'America/New_York',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TRIGGER trg_site_updated
BEFORE UPDATE ON site
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS station (
  station_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id        UUID NOT NULL REFERENCES site(site_id) ON DELETE RESTRICT,
  station_code   TEXT NOT NULL,         -- e.g. "recv-desk-1"
  station_name   TEXT NOT NULL,
  station_token_hash TEXT NULL,         -- optional: for fixed PCs
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(site_id, station_code)
);
CREATE TRIGGER trg_station_updated
BEFORE UPDATE ON station
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS location (
  location_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id        UUID NOT NULL REFERENCES site(site_id) ON DELETE RESTRICT,
  location_code  TEXT NOT NULL,         -- e.g. "A-03-02"
  location_name  TEXT NULL,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(site_id, location_code)
);
CREATE TRIGGER trg_location_updated
BEFORE UPDATE ON location
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS item (
  item_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id      UUID NOT NULL REFERENCES site(site_id) ON DELETE RESTRICT,
  item_code    TEXT NOT NULL,     -- internal SKU
  description  TEXT NULL,
  uom          TEXT NOT NULL DEFAULT 'ea',
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(site_id, item_code)
);
CREATE TRIGGER trg_item_updated
BEFORE UPDATE ON item
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS work_order (
  work_order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id       UUID NOT NULL REFERENCES site(site_id) ON DELETE RESTRICT,
  wo_code       TEXT NOT NULL,          -- "WO-7788"
  item_id       UUID NULL REFERENCES item(item_id) ON DELETE SET NULL,
  target_qty    NUMERIC(18,3) NULL,
  uom           TEXT NULL,
  status        TEXT NOT NULL DEFAULT 'open', -- open|closed|hold
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(site_id, wo_code)
);
CREATE TRIGGER trg_work_order_updated
BEFORE UPDATE ON work_order
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Material lots / produced lots are both "lots"
CREATE TABLE IF NOT EXISTS lot (
  lot_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id       UUID NOT NULL REFERENCES site(site_id) ON DELETE RESTRICT,
  lot_code      TEXT NOT NULL,          -- "LOT-88921" (your internal label)
  item_id       UUID NULL REFERENCES item(item_id) ON DELETE SET NULL,
  lot_type      TEXT NOT NULL DEFAULT 'material', -- material|wip|finished
  supplier_lot  TEXT NULL,
  status        TEXT NOT NULL DEFAULT 'active',   -- active|consumed|scrapped|shipped
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(site_id, lot_code)
);
CREATE TRIGGER trg_lot_updated
BEFORE UPDATE ON lot
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Optional: container (case/pallet) - used later for packing/shipping
CREATE TABLE IF NOT EXISTS container (
  container_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id        UUID NOT NULL REFERENCES site(site_id) ON DELETE RESTRICT,
  container_code TEXT NOT NULL,         -- "PAL-000293"
  container_type TEXT NOT NULL DEFAULT 'pallet', -- pallet|case|tote
  status         TEXT NOT NULL DEFAULT 'open',   -- open|closed|shipped
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(site_id, container_code)
);
CREATE TRIGGER trg_container_updated
BEFORE UPDATE ON container
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------
-- Scan telemetry (vendor-neutral)
-- -------------------------
CREATE TABLE IF NOT EXISTS scan_event (
  event_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id         UUID NULL REFERENCES site(site_id) ON DELETE SET NULL,
  station_id      UUID NULL REFERENCES station(station_id) ON DELETE SET NULL,
  user_id         UUID NULL REFERENCES app_user(user_id) ON DELETE SET NULL,

  ts              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  data            TEXT NOT NULL,
  symbology       TEXT NULL,

  source_mode     TEXT NOT NULL DEFAULT 'unknown', -- wedge|intent|camera|sdk|unknown
  vendor          TEXT NULL,                       -- zebra|honeywell|datalogic|generic|unknown
  device_id       TEXT NULL,
  session_id      UUID NULL,

  screen          TEXT NULL,       -- RECEIVE|MOVE|CONSUME|...
  expected_type   TEXT NULL,       -- LOT|WO|LOC|ITEM|...
  raw_json        JSONB NULL
);

CREATE INDEX IF NOT EXISTS ix_scan_event_ts ON scan_event(ts DESC);
CREATE INDEX IF NOT EXISTS ix_scan_event_data ON scan_event(data);

-- -------------------------
-- Transactions (MVP)
-- -------------------------

-- Receive: creates or links a lot into inventory at a location
CREATE TABLE IF NOT EXISTS txn_receive (
  receive_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id        UUID NOT NULL REFERENCES site(site_id) ON DELETE RESTRICT,
  station_id     UUID NULL REFERENCES station(station_id) ON DELETE SET NULL,
  user_id        UUID NULL REFERENCES app_user(user_id) ON DELETE SET NULL,

  ts             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  item_id        UUID NULL REFERENCES item(item_id) ON DELETE SET NULL,
  supplier_lot   TEXT NULL,
  lot_id         UUID NOT NULL REFERENCES lot(lot_id) ON DELETE RESTRICT,
  qty            NUMERIC(18,3) NOT NULL,
  uom            TEXT NOT NULL DEFAULT 'ea',

  to_location_id UUID NULL REFERENCES location(location_id) ON DELETE SET NULL,

  notes          TEXT NULL
);
CREATE INDEX IF NOT EXISTS ix_txn_receive_ts ON txn_receive(ts DESC);
CREATE INDEX IF NOT EXISTS ix_txn_receive_lot ON txn_receive(lot_id);

-- Move: moves a lot between locations
CREATE TABLE IF NOT EXISTS txn_move (
  move_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id        UUID NOT NULL REFERENCES site(site_id) ON DELETE RESTRICT,
  station_id     UUID NULL REFERENCES station(station_id) ON DELETE SET NULL,
  user_id        UUID NULL REFERENCES app_user(user_id) ON DELETE SET NULL,

  ts             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  lot_id         UUID NOT NULL REFERENCES lot(lot_id) ON DELETE RESTRICT,
  qty            NUMERIC(18,3) NULL, -- null means "entire lot" if you choose that model
  uom            TEXT NULL,

  from_location_id UUID NULL REFERENCES location(location_id) ON DELETE SET NULL,
  to_location_id   UUID NULL REFERENCES location(location_id) ON DELETE SET NULL,

  notes          TEXT NULL
);
CREATE INDEX IF NOT EXISTS ix_txn_move_ts ON txn_move(ts DESC);
CREATE INDEX IF NOT EXISTS ix_txn_move_lot ON txn_move(lot_id);

-- Consume: ties a material lot to a work order (genealogy foundation)
CREATE TABLE IF NOT EXISTS txn_consume (
  consume_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id        UUID NOT NULL REFERENCES site(site_id) ON DELETE RESTRICT,
  station_id     UUID NULL REFERENCES station(station_id) ON DELETE SET NULL,
  user_id        UUID NULL REFERENCES app_user(user_id) ON DELETE SET NULL,

  ts             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  work_order_id  UUID NOT NULL REFERENCES work_order(work_order_id) ON DELETE RESTRICT,
  lot_id         UUID NOT NULL REFERENCES lot(lot_id) ON DELETE RESTRICT,

  qty            NUMERIC(18,3) NOT NULL,
  uom            TEXT NOT NULL DEFAULT 'ea',

  step_code      TEXT NULL, -- optional process step id for later
  notes          TEXT NULL
);
CREATE INDEX IF NOT EXISTS ix_txn_consume_ts ON txn_consume(ts DESC);
CREATE INDEX IF NOT EXISTS ix_txn_consume_wo ON txn_consume(work_order_id);
CREATE INDEX IF NOT EXISTS ix_txn_consume_lot ON txn_consume(lot_id);

-- Evidence: which scan events were used to support a transaction (optional but powerful)
CREATE TABLE IF NOT EXISTS txn_evidence (
  evidence_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id        UUID NULL REFERENCES site(site_id) ON DELETE SET NULL,
  ts             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  txn_type       TEXT NOT NULL, -- receive|move|consume|...
  txn_id         UUID NOT NULL, -- the UUID of the txn_* row
  scan_event_id  UUID NOT NULL REFERENCES scan_event(event_id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS ix_txn_evidence_txn ON txn_evidence(txn_type, txn_id);

-- -------------------------
-- Seed minimal roles
-- -------------------------
INSERT INTO app_role(role_name)
VALUES ('admin'), ('operator'), ('supervisor')
ON CONFLICT (role_name) DO NOTHING;
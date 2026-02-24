-- V2__inventory_views_and_seed.sql
-- Adds: seed data + inventory-derived views + a few constraints

BEGIN;

-- -----------------------------------
-- 1) Constraints / hygiene
-- -----------------------------------

-- Make MOVE deterministic for MVP: require qty + uom
ALTER TABLE txn_move
  ALTER COLUMN qty SET NOT NULL;

ALTER TABLE txn_move
  ALTER COLUMN uom SET NOT NULL;

-- Optional prefix checks (safe, but can be loosened later)
-- If you prefer not to enforce prefixes yet, comment these out.

ALTER TABLE work_order
  ADD CONSTRAINT chk_work_order_code_prefix
  CHECK (wo_code ~* '^(WO-|WO:).+');

ALTER TABLE lot
  ADD CONSTRAINT chk_lot_code_prefix
  CHECK (lot_code ~* '^(LOT-|LOT:).+');

ALTER TABLE location
  ADD CONSTRAINT chk_location_code_format
  CHECK (location_code ~* '^[A-Z0-9]+(-[A-Z0-9]+){1,3}$'); -- e.g. A-03-02

ALTER TABLE container
  ADD CONSTRAINT chk_container_code_prefix
  CHECK (container_code ~* '^(PAL-|PAL:|CASE-|CASE:|TOTE-|TOTE:).+');

-- -----------------------------------
-- 2) Seed minimal data (idempotent)
-- -----------------------------------

-- Default site
INSERT INTO site (site_code, site_name, timezone)
VALUES ('plant-1', 'Default Plant', 'America/New_York')
ON CONFLICT (site_code) DO NOTHING;

-- Default station (good for a receiving desk PC)
INSERT INTO station (site_id, station_code, station_name)
SELECT s.site_id, 'recv-desk-1', 'Receiving Desk 1'
FROM site s
WHERE s.site_code = 'plant-1'
ON CONFLICT (site_id, station_code) DO NOTHING;

-- Default locations
INSERT INTO location (site_id, location_code, location_name)
SELECT s.site_id, v.location_code, v.location_name
FROM site s
CROSS JOIN (VALUES
  ('RECV-01', 'Receiving Area'),
  ('STAGE-01', 'Staging'),
  ('WH-01', 'Warehouse'),
  ('LINE-01', 'Line 1')
) AS v(location_code, location_name)
WHERE s.site_code = 'plant-1'
ON CONFLICT (site_id, location_code) DO NOTHING;

-- Default admin user (password_hash left NULL for now)
-- You can later set a hash once auth is implemented.
INSERT INTO app_user (username, display_name, is_active)
VALUES ('admin', 'Admin', TRUE)
ON CONFLICT (username) DO NOTHING;

-- Ensure admin has admin role
INSERT INTO user_role (user_id, role_id)
SELECT u.user_id, r.role_id
FROM app_user u
JOIN app_role r ON r.role_name = 'admin'
WHERE u.username = 'admin'
ON CONFLICT DO NOTHING;

-- -----------------------------------
-- 3) Inventory-derived view (MVP)
-- -----------------------------------
-- Goal: for each LOT, where is it and how much is left?

-- Interpretation:
-- - Receive adds qty at to_location
-- - Move subtracts qty from from_location and adds qty to to_location
-- - Consume subtracts qty from the lot (no location dimension here)
--   For MVP we treat consume as reducing total on-hand for the lot.
--   (Later you can add consume_location_id if needed.)

CREATE OR REPLACE VIEW v_lot_location_balance AS
WITH
received AS (
  SELECT
    r.site_id,
    r.lot_id,
    r.to_location_id AS location_id,
    SUM(r.qty) AS qty
  FROM txn_receive r
  WHERE r.to_location_id IS NOT NULL
  GROUP BY r.site_id, r.lot_id, r.to_location_id
),
moved_in AS (
  SELECT
    m.site_id,
    m.lot_id,
    m.to_location_id AS location_id,
    SUM(m.qty) AS qty
  FROM txn_move m
  WHERE m.to_location_id IS NOT NULL
  GROUP BY m.site_id, m.lot_id, m.to_location_id
),
moved_out AS (
  SELECT
    m.site_id,
    m.lot_id,
    m.from_location_id AS location_id,
    SUM(m.qty) AS qty
  FROM txn_move m
  WHERE m.from_location_id IS NOT NULL
  GROUP BY m.site_id, m.lot_id, m.from_location_id
),
consumed AS (
  SELECT
    c.site_id,
    c.lot_id,
    SUM(c.qty) AS qty
  FROM txn_consume c
  GROUP BY c.site_id, c.lot_id
),
-- balance per lot/location ignoring consume (locationless) first
loc_balance AS (
  SELECT site_id, lot_id, location_id, SUM(qty) AS qty
  FROM (
    SELECT site_id, lot_id, location_id, qty FROM received
    UNION ALL
    SELECT site_id, lot_id, location_id, qty FROM moved_in
    UNION ALL
    SELECT site_id, lot_id, location_id, -qty FROM moved_out
  ) x
  GROUP BY site_id, lot_id, location_id
),
-- total per lot for proportioning consume (optional logic)
lot_total AS (
  SELECT site_id, lot_id, SUM(qty) AS total_qty
  FROM loc_balance
  GROUP BY site_id, lot_id
)
SELECT
  lb.site_id,
  lb.lot_id,
  lb.location_id,
  -- MVP choice:
  -- subtract consume proportionally across locations if the lot is split.
  -- If you don’t like proportional allocation, we can keep consume separate.
  CASE
    WHEN lt.total_qty IS NULL OR lt.total_qty = 0 THEN lb.qty
    ELSE
      lb.qty - (COALESCE(c.qty, 0) * (lb.qty / lt.total_qty))
  END AS qty_on_hand_est
FROM loc_balance lb
JOIN lot_total lt
  ON lt.site_id = lb.site_id AND lt.lot_id = lb.lot_id
LEFT JOIN consumed c
  ON c.site_id = lb.site_id AND c.lot_id = lb.lot_id;

-- Convenience view: show codes + friendly names
CREATE OR REPLACE VIEW v_inventory_on_hand AS
SELECT
  s.site_code,
  l.lot_code,
  i.item_code,
  i.description AS item_description,
  loc.location_code,
  v.qty_on_hand_est
FROM v_lot_location_balance v
JOIN site s ON s.site_id = v.site_id
JOIN lot l ON l.lot_id = v.lot_id
LEFT JOIN item i ON i.item_id = l.item_id
LEFT JOIN location loc ON loc.location_id = v.location_id
WHERE v.qty_on_hand_est IS NOT NULL
  AND v.qty_on_hand_est > 0;

COMMIT;
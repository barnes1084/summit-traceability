# Next Logical Step After Repo Creation

Once repo exists, the correct build order is:

1. Docker + Postgres setup
2. Database schema (DDL)
3. Minimal API project
4. Minimal Angular PWA
5. Scan ingestion component
6. Transaction endpoints

Not frontend first.
Not Android first.
Database + API first.

---
this is designed to be a clean **vendor-neutral scan ingestion interface** that lets you support:

* USB/Bluetooth “keyboard wedge” scanners on PCs
* Android rugged devices using **intent-based scanning** (via a thin wrapper app)
* Phones/tablets using camera scan (optional)
* Future expansion (RFID later) without changing your core app

The goal: **every scan becomes the same normalized event** before it ever touches business logic.

---

## 1) Core concept

### Separate into 3 layers

1. **Capture** (vendor/device-specific): gets raw scan text
2. **Normalize** (vendor-neutral): wraps it into a common event schema
3. **Interpret** (business): decides what the scan *means* based on current screen/state

So your UI doesn’t care if the scan came from Zebra intent, Honeywell intent, or a USB scanner.

---

## 2) Canonical scan event schema (vendor-neutral)

This is the only format your web app + API should accept.

### `ScanEvent` (canonical)

```json
{
  "eventId": "01HZY5Y9W8K9W5X9PZK7D5YV0A",
  "ts": "2026-02-21T15:40:12.345Z",
  "data": "LOT-88921",
  "dataFormat": "text",
  "symbology": "CODE128",
  "source": {
    "mode": "intent|wedge|camera|sdk",
    "vendor": "zebra|honeywell|datalogic|generic|unknown",
    "deviceId": "A9F3-2C1D",
    "deviceLabel": "Receiving-01",
    "appId": "summit-scan-bridge",
    "sessionId": "b7d1c8c2-7c2c-4b2a-9b2d-3c91a2c1e0e9"
  },
  "context": {
    "userId": "dbarnes",
    "siteId": "plant-1",
    "stationId": "recv-desk-1",
    "screen": "RECEIVE|MOVE|CONSUME|PACK|SHIP|UNKNOWN",
    "workflowInstanceId": "wo-7788:consume:step2",
    "expectedScanType": "WORK_ORDER|LOT|LOCATION|ITEM|PALLET|UNKNOWN"
  },
  "meta": {
    "raw": {
      "intentAction": "…",
      "intentExtras": { }
    }
  }
}
```

### Why this works

* `data` is the only thing you always have
* everything else is optional, but **massively improves reliability**
* your **business logic reads `context.screen` + `expectedScanType`**, not vendor details

---

## 3) Two ingestion paths (both vendor-neutral after normalization)

### Path A — Web app (keyboard wedge)

Use a focused input field (hidden or visible) on each workflow screen.

**Mechanism**

* USB scanner “types” + sends Enter
* JS captures the value, clears field, emits `ScanEvent` with `source.mode="wedge"`

**Pros**

* Zero device-specific code
* Works on PCs instantly

**Cons**

* Depends on focus
* Less metadata

### Path B — Android wrapper bridge (intent-based)

A tiny Android app receives manufacturer intents and forwards to your web app.

**Mechanism**

* BroadcastReceiver catches vendor intent
* Normalizes into canonical `ScanEvent`
* Forwards to web UI via one of:

  * **WebView JS bridge** (best if app uses WebView)
  * **Local WebSocket** to the PWA
  * **HTTPS POST** to local API (works even without WebView)

**Pros**

* No focus problems
* Metadata (symbology, source)
* Vendor neutral at the boundary

**Cons**

* Requires installing wrapper on rugged devices

---

## 4) Where do scans go: UI-first or API-first?

You want **UI-first** for workflow correctness, **API-backed** for durability.

### Recommended flow

1. Scan arrives → **UI receives it** (web or wrapper)
2. UI validates quick rules (length, prefix, etc.)
3. UI submits to API as a **transaction** (not just “a scan”)

Because traceability isn’t “I saw a barcode.”
It’s “I consumed *this* lot into *that* work order at *this* step.”

So:

* `ScanEvent` = input primitive
* `Transaction` = durable record

---

## 5) API design: small + strong

### A) Optional: raw scan endpoint (for telemetry/debug)

`POST /api/scan-events`

Stores recent events (24–72 hrs) for troubleshooting devices, adoption, and scan quality.

### B) Primary: transactional endpoints (traceability truth)

Examples:

* `POST /api/receive`
* `POST /api/move`
* `POST /api/consume`
* `POST /api/pack`
* `POST /api/ship`

Each accepts the current workflow state + scans involved.

**Example: consume**

```json
{
  "workOrderId": "WO-7788",
  "materialLotId": "LOT-88921",
  "qty": 12.5,
  "uom": "lb",
  "machineId": "MIX-02",
  "operatorId": "dbarnes",
  "ts": "2026-02-21T15:41:01.001Z",
  "scanEvidence": [
    { "eventId": "01HZY5Y9W8K9W5X9PZK7D5YV0A" }
  ]
}
```

---

## 6) Scan interpretation: make it deterministic

To keep scans vendor-neutral and fast, standardize how your system knows what was scanned.

### Best practice: typed barcodes (prefix strategy)

Examples:

* `WO:7788`
* `LOT:88921`
* `LOC:A-03-02`
* `ITEM:123456`
* `PAL:000293`

This eliminates guessing and makes adoption easier.

### If you can’t control labels yet

Use a **resolver service**:

`POST /api/resolve-scan`

```json
{ "data": "88921" }
```

Returns:

```json
{
  "candidates": [
    { "type": "LOT", "id": "LOT-88921", "confidence": 0.92 },
    { "type": "ITEM", "id": "ITEM-88921", "confidence": 0.21 }
  ]
}
```

UI then prompts the operator if ambiguous.

---

## 7) Reliability rules (this prevents duplicates + phantom scans)

### A) Idempotency

Scanners sometimes double-fire or operators double-scan.

Require:

* `eventId` unique (ULID/UUID)
* API accepts `Idempotency-Key: <eventId>` header

### B) Debounce window (UI-side)

Ignore identical `data` from same `deviceId` within e.g. 250–500ms unless screen expects multiples.

### C) Audit trail

Every transaction stores:

* who
* deviceId/stationId (if present)
* eventIds used as evidence
* timestamps

This is gold during disputes.

---

## 8) Security model (minimal but solid)

* Devices authenticate with either:

  * user login tokens (operator logged in)
  * **station token** for fixed PCs (“Shipping Desk”)
  * wrapper app uses station token + operator badge scan in UI

Don’t start with per-device certificates—too heavy for SMB.

---

## 9) What you implement first (MVP checklist)

1. Canonical `ScanEvent` model
2. Web wedge capture component (reusable)
3. Prefix strategy (WO:/LOT:/LOC:) + resolver fallback
4. Transaction endpoints for 3 workflows:

   * Receive
   * Move
   * Consume
5. Optional: `scan-events` telemetry table (helps support)

Then later:

* Android wrapper bridge (intent) for rugged fleets
* Offline queue + sync
* Advanced reporting

---

## 10) How this stays vendor-neutral long-term

You only ever write vendor-specific code in **adapters**:

* Adapter: Zebra intent → canonical event
* Adapter: Honeywell intent → canonical event
* Adapter: Datalogic intent → canonical event
* Adapter: Wedge → canonical event

Everything else (UI + API + database) is identical across customers.

---

## Making the databases
The initial schema in this order:

1. **Auth & audit**

* users, roles, sessions, audit_log

2. **Master data**

* sites, stations, locations, items, printers, machines (optional)

3. **Traceability objects**

* work_orders
* lots (material lots)
* containers (case/pallet)
* inventory_balances (optional, or compute from moves)

4. **Transactions**

* receive_txn
* move_txn
* consume_txn
* pack_txn
* ship_txn

5. **Scan telemetry (optional but useful)**

* scan_events

---

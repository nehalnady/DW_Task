# NiFi Flow Configuration Guide

## CDC Pipeline: Kafka → NiFi → PostgreSQL Data Warehouse

This guide walks you through building the NiFi data flow that pulls CDC events
from Kafka and writes them to the PostgreSQL data warehouse.

---

## Prerequisites

- NiFi is running at http://localhost:8080/nifi
- Kafka is running with the topic `cdc.testdb.users` populated by Debezium
- PostgreSQL DW is running at `warehouse:5432`
- Debezium connector is registered and running

---

## Architecture of the NiFi Flow

```
[ConsumeKafkaRecord]
        |
        v
[EvaluateJsonPath]  ← extract id, name, email, op, ts_ms
        |
        v
[RouteOnAttribute]  ← branch on cdc_operation (c/u/d)
        |
   +----|-------+----------+
   v            v          v
[PutSQL]    [PutSQL]   [PutSQL]
 INSERT      UPSERT     DELETE-mark
        \       |       /
         v      v      v
       [LogAttribute]  (for debugging)
```

---

## Step 1 — Add PostgreSQL JDBC Driver to NiFi

NiFi needs the PostgreSQL JDBC driver JAR to talk to the DW.

1. Download PostgreSQL JDBC driver:
   ```
   wget https://jdbc.postgresql.org/download/postgresql-42.7.3.jar
   ```

2. Copy it into the NiFi container:
   ```bash
   docker cp postgresql-42.7.3.jar cdc_nifi:/opt/nifi/nifi-current/lib/
   ```

3. Restart NiFi (or use the UI — NiFi hot-loads JARs in `/lib`):
   ```bash
   docker restart cdc_nifi
   ```

---

## Step 2 — Create a DBCPConnectionPool Controller Service

In the NiFi canvas:

1. Click the **gear icon** (hamburger → Controller Services) at the top right.
2. Click **+** to add a service.
3. Search for `DBCPConnectionPool` → Add.
4. Configure the service:

| Property | Value |
|---|---|
| Database Connection URL | `jdbc:postgresql://warehouse:5432/datawarehouse` |
| Database Driver Class Name | `org.postgresql.Driver` |
| Database Driver Location(s) | `/opt/nifi/nifi-current/lib/postgresql-42.7.3.jar` |
| Database User | `dw_user` |
| Password | `dw_password` |

5. Click **Enable** (lightning bolt icon).

---

## Step 3 — Build the NiFi Flow

### 3.1 — Processor: ConsumeKafkaRecord

Drag a **ConsumeKafkaRecord** processor onto the canvas.

**Properties:**

| Property | Value |
|---|---|
| Kafka Brokers | `kafka:9092` |
| Topic Name(s) | `cdc.testdb.users` |
| Group ID | `nifi-cdc-consumer` |
| Offset Reset | `earliest` |
| Record Reader | `JsonTreeReader` (create via + button) |
| Record Writer | `JsonRecordSetWriter` (create via + button) |
| Honor Transactions | `false` |

**JsonTreeReader** — Leave all defaults. This parses the flat Debezium JSON.

**Relationships to route:**
- `success` → EvaluateJsonPath
- `failure` → LogAttribute (for debugging)

---

### 3.2 — Processor: EvaluateJsonPath

Extracts individual fields from each CDC event.

**Properties:**

| Property | Value |
|---|---|
| Destination | `flowfile-attribute` |
| Return Type | `auto-detect` |

**Add the following expressions:**

| Attribute Name | JsonPath Expression |
|---|---|
| `cdc_id` | `$.id` |
| `cdc_name` | `$.name` |
| `cdc_email` | `$.email` |
| `cdc_created_at` | `$.created_at` |
| `cdc_updated_at` | `$.updated_at` |
| `cdc_operation` | `$.op` |
| `cdc_timestamp` | `$.ts_ms` |

> **Note:** Because we used Debezium's `ExtractNewRecordState` SMT with
> `add.fields=op,ts_ms`, the Kafka message is already a flat JSON
> (not nested in `before`/`after` envelopes).

**Relationships:**
- `matched` → RouteOnAttribute
- `unmatched` → RouteOnAttribute (same destination is fine here)
- `failure` → LogAttribute

---

### 3.3 — Processor: RouteOnAttribute

Routes FlowFiles to different SQL processors based on the CDC operation type.

**Routing Strategy:** `Route to Property name`

**Add these properties:**

| Route Name | Value |
|---|---|
| `insert` | `${cdc_operation:equals('c')}` |
| `update` | `${cdc_operation:equals('u')}` |
| `delete` | `${cdc_operation:equals('d')}` |

**Relationships:**
- `insert` → PutSQL (Insert processor)
- `update` → PutSQL (Upsert processor)
- `delete` → PutSQL (Delete-mark processor)
- `unmatched` → LogAttribute

---

### 3.4 — Processor: PutSQL (for INSERT)

Handles new rows (`op = c`).

**Properties:**

| Property | Value |
|---|---|
| JDBC Connection Pool | `DBCPConnectionPool` (configured above) |
| SQL Statement | See below |

**SQL Statement:**
```sql
INSERT INTO dw_users (id, name, email, created_at, updated_at, cdc_operation, cdc_timestamp)
VALUES (
    ${cdc_id},
    '${cdc_name}',
    '${cdc_email}',
    TO_TIMESTAMP(${cdc_created_at:isEmpty():ifElse('0', cdc_created_at)}::BIGINT / 1000),
    TO_TIMESTAMP(${cdc_updated_at:isEmpty():ifElse('0', cdc_updated_at)}::BIGINT / 1000),
    '${cdc_operation}',
    ${cdc_timestamp}
)
```

**Relationships:**
- `success` → LogAttribute (or terminate)
- `failure` → LogAttribute

---

### 3.5 — Processor: PutSQL (for UPDATE)

Handles updates (`op = u`). We INSERT a new CDC row (append-log pattern).

**Properties:**

| Property | Value |
|---|---|
| JDBC Connection Pool | `DBCPConnectionPool` |
| SQL Statement | See below |

**SQL Statement:**
```sql
INSERT INTO dw_users (id, name, email, created_at, updated_at, cdc_operation, cdc_timestamp)
VALUES (
    ${cdc_id},
    '${cdc_name}',
    '${cdc_email}',
    TO_TIMESTAMP(${cdc_created_at:isEmpty():ifElse('0', cdc_created_at)}::BIGINT / 1000),
    TO_TIMESTAMP(${cdc_updated_at:isEmpty():ifElse('0', cdc_updated_at)}::BIGINT / 1000),
    '${cdc_operation}',
    ${cdc_timestamp}
)
```

> This is an **insert-log model**: every UPDATE creates a new DW row.
> The `dw_users_latest` view resolves the latest state by ordering on `cdc_timestamp DESC`.

---

### 3.6 — Processor: PutSQL (for DELETE)

Soft-marks deleted records (`op = d`) by inserting a tombstone row.

**SQL Statement:**
```sql
INSERT INTO dw_users (id, name, email, created_at, updated_at, cdc_operation, cdc_timestamp)
VALUES (
    ${cdc_id},
    '${cdc_name:isEmpty():ifElse(NULL, cdc_name)}',
    '${cdc_email:isEmpty():ifElse(NULL, cdc_email)}',
    NULL,
    NULL,
    'd',
    ${cdc_timestamp}
)
```

---

### 3.7 — Processor: LogAttribute (optional)

Add a **LogAttribute** processor connected to `failure` relationships of all
PutSQL processors. This logs error detail to `nifi-app.log` for debugging.

**Properties:**

| Property | Value |
|---|---|
| Log Level | `warn` |
| Attributes to Log | `.*` |

---

## Step 4 — Enable and Start the Flow

1. Select all processors (Ctrl+A)
2. Right-click → **Enable**
3. Right-click → **Start**
4. Watch the status indicators turn green (active) with data flowing

---

## Step 5 — Monitor the Flow

- **NiFi Bulletin Board** (top-right bell icon): shows errors
- **Data Provenance** (right-click processor → View data provenance): trace a FlowFile
- **Queue inspection** (click the connection queue number): see queued messages

---

## Verification Queries (run in PostgreSQL)

```sql
-- See all CDC events
SELECT * FROM dw_users ORDER BY dw_id;

-- See current state of each user
SELECT * FROM dw_users_latest;

-- See only active (non-deleted) users
SELECT * FROM dw_users_active;

-- Count events by operation type
SELECT cdc_operation, COUNT(*) FROM dw_users GROUP BY cdc_operation;
```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| ConsumeKafkaRecord shows no data | Check topic name is `cdc.testdb.users`, check connector status |
| EvaluateJsonPath `unmatched` | Log the raw FlowFile content — field names may differ |
| PutSQL failure | Check DW connection URL, user/password, and JDBC driver path |
| NiFi can't reach `warehouse:5432` | Both containers must be on `cdc_network` |

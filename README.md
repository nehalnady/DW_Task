# CDC Pipeline: MySQL → Debezium → Kafka → NiFi → Data Warehouse

A **production-style, real-time Change Data Capture pipeline** built entirely on Docker.
Any INSERT, UPDATE, or DELETE in MySQL is automatically captured via the binary log,
streamed through Kafka, processed by NiFi, and stored in a PostgreSQL Data Warehouse.

---

## Architecture

```
┌──────────────┐     binlog     ┌───────────────┐   Kafka topic    ┌──────────────┐
│  MySQL 8.0   │ ─────────────► │   Debezium    │ ───────────────► │    Kafka     │
│  (testdb)    │                │ (MySQL CDC)   │ cdc.testdb.users │  (Broker)    │
└──────────────┘                └───────────────┘                  └──────┬───────┘
                                                                           │
                                                                           ▼
                                                                  ┌──────────────┐
                                                                  │  Apache NiFi │
                                                                  │              │
                                                                  │ ConsumeKafka │
                                                                  │     ↓        │
                                                                  │ EvalJsonPath │
                                                                  │     ↓        │
                                                                  │ RouteOnAttr  │
                                                                  │  (c/u/d)     │
                                                                  │     ↓        │
                                                                  │    PutSQL    │
                                                                  └──────┬───────┘
                                                                         │
                                                                         ▼
                                                                ┌──────────────────┐
                                                                │  PostgreSQL DW   │
                                                                │ (datawarehouse)  │
                                                                │  dw_users table  │
                                                                └──────────────────┘
```

### How Debezium Works (binlog-based CDC)

Debezium acts like a **MySQL replication slave**. It connects to MySQL and reads
the **binary log (binlog)** — the same stream MySQL uses for primary→replica
replication — but instead of applying changes to another MySQL, it publishes them
as JSON events to Kafka. This is **pure real-time CDC, not polling**.

Each Kafka message contains:
- The operation type (`op`): `c` (create), `u` (update), `d` (delete), `r` (read/snapshot)
- The row data (after the `ExtractNewRecordState` SMT: flat JSON)
- A timestamp in milliseconds (`ts_ms`)

---

## Project Structure

```
DW_Task/
├── docker-compose.yml           # All services in one file
├── mysql/
│   ├── my.cnf                   # MySQL binlog config
│   ├── init.sql                 # Schema + seed data + Debezium grants
│   └── test-queries.sql         # INSERT / UPDATE / DELETE test queries
├── debezium/
│   ├── connector.json           # Debezium MySQL connector config
│   └── register-connector.sh   # Register connector via REST API
├── kafka/
│   ├── create-topics.sh         # Explicitly create Kafka topics
│   └── consume-messages.sh     # CLI consumer for monitoring
├── nifi/
│   └── flow-guide.md           # Step-by-step NiFi flow build guide
├── warehouse/
│   └── schema.sql               # PostgreSQL DW schema + views
├── scripts/
│   ├── start.sh                 # Ordered startup script
│   └── test-pipeline.sh        # End-to-end test
└── README.md
```

---

## Quick Start

### Prerequisites

- Docker Engine ≥ 24.x
- Docker Compose plugin (`docker compose`)
- `curl`, `bash`

### 1 — Start All Services

```bash
# Option A: Use the helper script (recommended)
bash scripts/start.sh

# Option B: Manual Docker Compose
docker compose up -d
```

Services and their URLs:

| Service | URL / Port |
|---|---|
| MySQL | `localhost:3306` |
| Zookeeper | `localhost:2181` |
| Kafka | `localhost:29092` |
| Kafka UI | http://localhost:8090 |
| Kafka Connect (Debezium) | http://localhost:8083 |
| Apache NiFi | http://localhost:8080/nifi |
| PostgreSQL DW | `localhost:5432` |

### 2 — Register the Debezium Connector

```bash
bash debezium/register-connector.sh
```

This calls the Kafka Connect REST API to register the MySQL CDC connector.

Verify the connector status:
```bash
curl http://localhost:8083/connectors/mysql-cdc-connector/status | python3 -m json.tool
```

Expected output: `"state": "RUNNING"`

### 3 — Build the NiFi Flow

Follow the detailed instructions in [`nifi/flow-guide.md`](nifi/flow-guide.md).

**High-level steps:**
1. Open http://localhost:8080/nifi
2. Create a `DBCPConnectionPool` for PostgreSQL
3. Add: `ConsumeKafkaRecord` → `EvaluateJsonPath` → `RouteOnAttribute` → 3× `PutSQL`
4. Start the flow

### 4 — Insert Test Data into MySQL

```bash
# Run all test queries (INSERT + UPDATE + DELETE)
docker exec -i cdc_mysql mysql -u cdc_user -pcdc_password testdb \
    < mysql/test-queries.sql
```

Or connect interactively:
```bash
docker exec -it cdc_mysql mysql -u cdc_user -pcdc_password testdb
```

### 5 — Watch Kafka Messages

```bash
# Show new messages in real time
bash kafka/consume-messages.sh

# Show all messages from the beginning
bash kafka/consume-messages.sh --from-beginning
```

Or use the Kafka UI at http://localhost:8090.

### 6 — Verify Data in the Data Warehouse

```bash
docker exec cdc_warehouse psql -U dw_user -d datawarehouse -c \
    "SELECT id, name, email, cdc_operation, TO_TIMESTAMP(cdc_timestamp/1000) AS event_time
     FROM dw_users ORDER BY dw_id;"
```

---

## Kafka Topics

| Topic | Purpose |
|---|---|
| `cdc.testdb.users` | CDC events for `testdb.users` (main data topic) |
| `cdc.schema.history` | Debezium tracks schema changes here |
| `cdc.connect.configs` | Kafka Connect internal config storage |
| `cdc.connect.offsets` | Kafka Connect offset tracking (CDC resume point) |
| `cdc.connect.status` | Kafka Connect task status |

---

## Debezium Event Format

After the `ExtractNewRecordState` SMT, each Kafka message looks like this:

**INSERT (`op: c`)**
```json
{
  "id": 4,
  "name": "Dave Brown",
  "email": "dave@example.com",
  "created_at": "2024-01-01T10:00:00Z",
  "updated_at": "2024-01-01T10:00:00Z",
  "op": "c",
  "ts_ms": 1704103200000
}
```

**UPDATE (`op: u`)**
```json
{
  "id": 1,
  "name": "Alice Johnson-Updated",
  "email": "alice.updated@example.com",
  "created_at": "2024-01-01T09:00:00Z",
  "updated_at": "2024-01-01T11:00:00Z",
  "op": "u",
  "ts_ms": 1704106800000
}
```

**DELETE (`op: d`)**
```json
{
  "id": 3,
  "name": "Carol Williams",
  "email": "carol@example.com",
  "op": "d",
  "ts_ms": 1704110400000
}
```

---

## Data Warehouse Tables & Views

| Object | Type | Description |
|---|---|---|
| `dw_users` | Table | Append-log of all CDC events with metadata |
| `dw_users_latest` | View | Most-recent state of each user |
| `dw_users_active` | View | Non-deleted users (latest state) |

**Key columns in `dw_users`:**

| Column | Type | Description |
|---|---|---|
| `cdc_operation` | `CHAR(1)` | `c` create · `u` update · `d` delete |
| `cdc_timestamp` | `BIGINT` | Binlog event time (Unix ms) |
| `cdc_loaded_at` | `TIMESTAMP` | When NiFi wrote this row to DW |
| `dw_id` | `BIGSERIAL` | DW surrogate key (auto-increment) |

---

## Useful Commands

```bash
# Check all container health
docker compose ps

# View Debezium connector logs
docker logs cdc_kafka_connect --tail=100 -f

# View NiFi logs
docker logs cdc_nifi --tail=100 -f

# List Kafka topics
docker exec cdc_kafka kafka-topics --bootstrap-server kafka:9092 --list

# Check connector lag (how many messages are unprocessed)
docker exec cdc_kafka kafka-consumer-groups \
    --bootstrap-server kafka:9092 \
    --group nifi-cdc-consumer \
    --describe

# Tear down everything (keeps volumes)
docker compose down

# Tear down and remove all data volumes (CLEAN SLATE)
docker compose down -v
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Connector state is `FAILED` | MySQL not ready or wrong credentials | Check `docker logs cdc_mysql`, verify `cdc_user` grants |
| No Kafka messages | Connector not registered or not running | Re-run `register-connector.sh`, check logs |
| NiFi can't connect to PostgreSQL | Wrong hostname or port | Use `warehouse:5432` inside Docker network |
| `dw_users` empty after test | NiFi flow not started | Start all processors in NiFi UI |
| Binlog not enabled | `my.cnf` not mounted | Verify volume mount in `docker-compose.yml` |

---

## Credentials Reference

| Service | Username | Password | Database |
|---|---|---|---|
| MySQL | `cdc_user` | `cdc_password` | `testdb` |
| MySQL root | `root` | `rootpassword` | — |
| PostgreSQL DW | `dw_user` | `dw_password` | `datawarehouse` |
| NiFi UI | `admin` | `adminpassword123` | — |

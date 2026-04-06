#!/usr/bin/env bash
# =============================================================================
# scripts/test-pipeline.sh
# Purpose: End-to-end pipeline test
#   1. Runs INSERT / UPDATE / DELETE in MySQL
#   2. Shows Kafka messages (5-second window)
#   3. Shows current DW state in PostgreSQL
# Usage:   bash scripts/test-pipeline.sh
# =============================================================================

set -euo pipefail

echo "============================================================"
echo " End-to-End CDC Pipeline Test"
echo "============================================================"

# --- Step 1: Run test SQL against MySQL -----------------------------------
echo ""
echo "[1/3] Running INSERT / UPDATE / DELETE in MySQL..."
docker exec cdc_mysql mysql \
    -u cdc_user -pcdc_password testdb \
    -e "
        -- INSERT
        INSERT INTO users (name, email) VALUES ('Test User A', 'testa@test.com');
        INSERT INTO users (name, email) VALUES ('Test User B', 'testb@test.com');

        -- UPDATE
        UPDATE users SET name='Test User A (updated)' WHERE email='testa@test.com';

        -- DELETE
        DELETE FROM users WHERE email='testb@test.com';

        SELECT 'MySQL state after test:' AS msg;
        SELECT * FROM users;
    "

echo ""
echo "[INFO] Waiting 5 seconds for Kafka events to propagate..."
sleep 5

# --- Step 2: Show recent Kafka messages -----------------------------------
echo ""
echo "[2/3] Last 10 Kafka messages on cdc.testdb.users:"
echo "--------------------------------------------------------------"

# Use --timeout-ms to read for a bounded time window
docker exec cdc_kafka kafka-console-consumer \
    --bootstrap-server kafka:9092 \
    --topic cdc.testdb.users \
    --from-beginning \
    --max-messages 10 \
    --timeout-ms 8000 \
    --property "print.key=false" \
    2>/dev/null || true

echo ""
echo "--------------------------------------------------------------"

# --- Step 3: Show DW state (requires NiFi flow to be running) ------------
echo ""
echo "[3/3] Data Warehouse state (requires NiFi flow to be active):"
echo "--------------------------------------------------------------"
docker exec cdc_warehouse psql \
    -U dw_user -d datawarehouse \
    -c "SELECT id, name, email, cdc_operation, TO_TIMESTAMP(cdc_timestamp/1000) AS event_time FROM dw_users ORDER BY dw_id DESC LIMIT 20;"

echo ""
echo "Active (non-deleted) users:"
docker exec cdc_warehouse psql \
    -U dw_user -d datawarehouse \
    -c "SELECT id, name, email FROM dw_users_active ORDER BY id;"

echo ""
echo "============================================================"
echo " Test complete!"
echo "============================================================"

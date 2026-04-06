#!/usr/bin/env bash
# =============================================================================
# scripts/start.sh
# Purpose: Start the full CDC pipeline in the correct boot order
# Usage:   bash scripts/start.sh
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "============================================================"
echo " CDC Pipeline Startup"
echo " MySQL → Debezium → Kafka → NiFi → PostgreSQL DW"
echo "============================================================"

# --- Step 1: Start infrastructure services --------------------------------
echo ""
echo "[1/5] Starting Zookeeper, Kafka, MySQL, PostgreSQL..."
cd "${PROJECT_ROOT}"
docker compose up -d zookeeper kafka mysql warehouse kafka-ui

# --- Step 2: Wait for MySQL to be healthy ---------------------------------
echo "[2/5] Waiting for MySQL to become healthy..."
until docker inspect --format='{{.State.Health.Status}}' cdc_mysql 2>/dev/null | grep -q "healthy"; do
    printf "."
    sleep 3
done
echo " MySQL is ready!"

# --- Step 3: Wait for Kafka to be healthy ---------------------------------
echo "[3/5] Waiting for Kafka to become healthy..."
until docker inspect --format='{{.State.Health.Status}}' cdc_kafka 2>/dev/null | grep -q "healthy"; do
    printf "."
    sleep 3
done
echo " Kafka is ready!"

# --- Step 4: Start Kafka Connect (Debezium) -------------------------------
echo "[4/5] Starting Kafka Connect (Debezium)..."
docker compose up -d kafka-connect

echo "Waiting for Kafka Connect to be ready..."
until curl -sf "http://localhost:8083/connectors" > /dev/null 2>&1; do
    printf "."
    sleep 5
done
echo " Kafka Connect is ready!"

# --- Step 5: Start NiFi ---------------------------------------------------
echo "[5/5] Starting Apache NiFi..."
docker compose up -d nifi

echo ""
echo "============================================================"
echo " All services started!"
echo ""
echo " Service URLs:"
echo "   Kafka Connect REST API: http://localhost:8083"
echo "   Kafka UI:               http://localhost:8090"
echo "   NiFi UI:                http://localhost:8080/nifi"
echo "   MySQL:                  localhost:3306 (db: testdb)"
echo "   PostgreSQL DW:          localhost:5432 (db: datawarehouse)"
echo ""
echo " Next steps:"
echo "   1. Register Debezium connector:"
echo "      bash debezium/register-connector.sh"
echo "   2. Build NiFi flow:"
echo "      Follow nifi/flow-guide.md"
echo "   3. Run test queries:"
echo "      bash scripts/test-pipeline.sh"
echo "============================================================"

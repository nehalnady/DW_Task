#!/usr/bin/env bash
# =============================================================================
# register-connector.sh
# Purpose: Register the Debezium MySQL CDC connector via Kafka Connect REST API
# Usage:   bash debezium/register-connector.sh
# =============================================================================

set -euo pipefail

CONNECT_URL="http://localhost:8083"
CONNECTOR_FILE="$(dirname "$0")/connector.json"

echo "============================================================"
echo " Debezium Connector Registration"
echo "============================================================"

# --- Wait for Kafka Connect to be ready ----------------------------------
echo "[1/3] Waiting for Kafka Connect to be ready..."
until curl -sf "${CONNECT_URL}/connectors" > /dev/null; do
    printf "."
    sleep 3
done
echo " Ready!"

# --- Check if connector already exists -----------------------------------
EXISTING=$(curl -s "${CONNECT_URL}/connectors" | grep -c "mysql-cdc-connector" || true)

if [ "$EXISTING" -gt "0" ]; then
    echo "[2/3] Connector already exists. Deleting and re-registering..."
    curl -s -X DELETE "${CONNECT_URL}/connectors/mysql-cdc-connector"
    sleep 2
else
    echo "[2/3] No existing connector found."
fi

# --- Register the connector ----------------------------------------------
echo "[3/3] Registering connector from ${CONNECTOR_FILE} ..."
RESPONSE=$(curl -s -o /tmp/connector-response.json -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    --data @"${CONNECTOR_FILE}" \
    "${CONNECT_URL}/connectors")

if [ "$RESPONSE" -eq 200 ] || [ "$RESPONSE" -eq 201 ]; then
    echo ""
    echo "✅  Connector registered successfully!"
    echo ""
    echo "Connector status:"
    sleep 3
    curl -s "${CONNECT_URL}/connectors/mysql-cdc-connector/status" | python3 -m json.tool
else
    echo ""
    echo "❌  Failed to register connector (HTTP ${RESPONSE})"
    cat /tmp/connector-response.json
    exit 1
fi

echo ""
echo "Kafka topic that will receive events: cdc.testdb.users"
echo "============================================================"

#!/usr/bin/env bash
# =============================================================================
# create-topics.sh
# Purpose: Explicitly create Kafka topics for the CDC pipeline
#           (Kafka auto-creates them anyway, but explicit creation gives
#            control over replication factor and partition count)
# Usage:   bash kafka/create-topics.sh
# =============================================================================

set -euo pipefail

KAFKA_CONTAINER="cdc_kafka"
BOOTSTRAP="kafka:9092"

echo "============================================================"
echo " Creating Kafka Topics"
echo "============================================================"

# Helper function
create_topic() {
    local TOPIC=$1
    local PARTITIONS=${2:-1}
    local REPLICATION=${3:-1}

    echo "Creating topic: ${TOPIC} (partitions=${PARTITIONS}, replication=${REPLICATION})"
    docker exec "${KAFKA_CONTAINER}" kafka-topics \
        --bootstrap-server "${BOOTSTRAP}" \
        --create \
        --if-not-exists \
        --topic "${TOPIC}" \
        --partitions "${PARTITIONS}" \
        --replication-factor "${REPLICATION}"
}

# --- CDC data topic (main events from Debezium) --------------------------
create_topic "cdc.testdb.users" 3 1

# --- Internal Kafka Connect topics (usually auto-created by Connect) ------
create_topic "cdc.connect.configs"  1 1
create_topic "cdc.connect.offsets"  1 1
create_topic "cdc.connect.status"   1 1

# --- Schema history topic (required by Debezium) -------------------------
create_topic "cdc.schema.history"   1 1

echo ""
echo "All topics created. Listing all topics:"
docker exec "${KAFKA_CONTAINER}" kafka-topics \
    --bootstrap-server "${BOOTSTRAP}" \
    --list

echo "============================================================"

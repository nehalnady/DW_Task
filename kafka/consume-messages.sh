#!/usr/bin/env bash
# =============================================================================
# consume-messages.sh
# Purpose: Consume and display CDC events from the cdc.testdb.users Kafka topic
#          Useful for verifying Debezium is producing events correctly
# Usage:   bash kafka/consume-messages.sh [--from-beginning]
# =============================================================================

set -euo pipefail

KAFKA_CONTAINER="cdc_kafka"
BOOTSTRAP="kafka:9092"
TOPIC="cdc.testdb.users"

FROM_BEGINNING=""
if [[ "${1:-}" == "--from-beginning" ]]; then
    FROM_BEGINNING="--from-beginning"
    echo "Reading from beginning of topic..."
fi

echo "============================================================"
echo " Consuming from Kafka Topic: ${TOPIC}"
echo " Press Ctrl+C to stop."
echo "============================================================"

# Use kafka-console-consumer to print each message on one line
# Then pipe through python for pretty JSON formatting (if available)
docker exec -it "${KAFKA_CONTAINER}" kafka-console-consumer \
    --bootstrap-server "${BOOTSTRAP}" \
    --topic "${TOPIC}" \
    --property "print.key=true" \
    --property "print.value=true" \
    --property "key.separator= | KEY: " \
    --property "print.timestamp=true" \
    ${FROM_BEGINNING}

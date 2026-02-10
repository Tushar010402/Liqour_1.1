#!/bin/bash
set -e

# LiquorPro Kafka Topic Initialization Script
# Run after Kafka is healthy: ./scripts/kafka-create-topics.sh

KAFKA_CONTAINER="liquorpro-kafka-prod"
BOOTSTRAP="localhost:9092"

echo "Creating Kafka topics..."

declare -A TOPICS=(
  ["sales-events"]=3
  ["inventory-events"]=3
  ["payment-events"]=2
  ["auth-events"]=1
  ["notification-events"]=2
  ["general-events"]=1
)

for TOPIC in "${!TOPICS[@]}"; do
  PARTITIONS=${TOPICS[$TOPIC]}
  echo "  Creating topic: $TOPIC (partitions=$PARTITIONS)"
  docker exec "$KAFKA_CONTAINER" /opt/kafka/bin/kafka-topics.sh \
    --create \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --partitions "$PARTITIONS" \
    --replication-factor 1 \
    --if-not-exists \
    --config retention.ms=604800000 \
    --config compression.type=snappy
done

echo ""
echo "Verifying topics..."
docker exec "$KAFKA_CONTAINER" /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server "$BOOTSTRAP"
echo ""
echo "Done. All topics created."

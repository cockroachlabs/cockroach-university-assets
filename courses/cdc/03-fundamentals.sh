#!/bin/bash
set -euxo pipefail

BRANCH=main
COMPOSE=/root/compose

# Create a temporary directory for the compose file
mkdir -p $COMPOSE

# Create a in-line docker-compose.yml
cat > $COMPOSE/docker-compose.yml <<EOF
version: '3.8'
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.3.0
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
    ports:
      - "2181:2181"

  kafka:
    image: confluentinc/cp-kafka:7.3.0
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
EOF

# Start the services
cd $COMPOSE
nohup docker-compose up -d > kafka_compose_log.out 2>&1 &
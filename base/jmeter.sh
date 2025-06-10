#!/bin.bash

echo "Download Apache Jmeter for load testing"

JMETER_VERSION=5.6.3
POSTGRES_VERSION=42.7.3

# apt install -y jmeter
wget -q https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz
tar -xzf apache-jmeter-${JMETER_VERSION}.tgz
mv apache-jmeter-${JMETER_VERSION} jmeter

# download the PostgreSQL JDBC driver and install into the Jmeter lib directory
wget -q -P /root/jmeter/lib https://jdbc.postgresql.org/download/postgresql-${POSTGRES_VERSION}.jar

# disable the HeapDumpOnOutOfMemoryError in the jmeter script
sed -i '/^DUMP="-XX:+HeapDumpOnOutOfMemoryError"/ s/^/# /' /root/jmeter/bin/jmeter

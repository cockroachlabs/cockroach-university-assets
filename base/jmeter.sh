#!/bin.bash

echo "[JMETER] Download Apache Jmeter for load testing"

## Variables
JMETER_VERSION=5.6.3
POSTGRES_VERSION=42.7.3

## jmeter
echo "[JMETER] Installing JMeter"
cd /tmp
wget -q https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz
tar -xzf apache-jmeter-${JMETER_VERSION}.tgz
mv apache-jmeter-${JMETER_VERSION} jmeter
mv jmeter /root/

## Make sure the /root/jmeter exists using IF
if [ ! -d /root/jmeter ]; then
    echo "[JMETER] JMeter directory does not exist ..."
    exit 1
fi


# download the PostgreSQL JDBC driver and install into the Jmeter lib directory
wget -q -P /root/jmeter/lib https://jdbc.postgresql.org/download/postgresql-${POSTGRES_VERSION}.jar

# disable the HeapDumpOnOutOfMemoryError in the jmeter script
sed -i '/^DUMP="-XX:+HeapDumpOnOutOfMemoryError"/ s/^/# /' /root/jmeter/bin/jmeter

echo "[JMETER] JMeter installation completed successfully."
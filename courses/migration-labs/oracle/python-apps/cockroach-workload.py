#!/usr/bin/env python3
"""
CockroachDB Workload Generator
Continuously inserts orders and order_fills into CockroachDB database
"""

import time
import random
from datetime import datetime
import argparse
import psycopg2
from psycopg2 import OperationalError, errors

# Connection parameters
CRDB_HOST = "localhost"
CRDB_PORT = "26257"
CRDB_USER = "root"
CRDB_DATABASE = "target"
CRDB_DSN = f"postgresql://{CRDB_USER}@{CRDB_HOST}:{CRDB_PORT}/{CRDB_DATABASE}?sslmode=disable"

def get_connection():
    """Create CockroachDB database connection"""
    try:
        connection = psycopg2.connect(CRDB_DSN)
        return connection
    except Exception as e:
        print(f"❌ Error connecting to CockroachDB: {e}")
        raise

def insert_order_with_fill(connection, account_id=1, symbol='ORCL', shares=100, cost=238.98, max_retries=3):
    """
    Insert one order and corresponding order_fill in a transaction
    Includes retry logic for serialization errors
    """
    attempt = 0
    while attempt < max_retries:
        try:
            cursor = connection.cursor()

            # Insert order (DEFAULT nextval will set order_id)
            cursor.execute("""
                INSERT INTO orders (
                    account_id, symbol, order_started,
                    total_shares_purchased, total_cost_of_order
                ) VALUES (%s, %s, NOW(), %s, %s)
                RETURNING order_id
            """, (account_id, symbol, shares, cost))

            order_id = cursor.fetchone()[0]

            # Insert order_fill (DEFAULT nextval will set fill_id)
            price = round(cost / shares, 2)
            cursor.execute("""
                INSERT INTO order_fills (
                    order_id, account_id, symbol, fill_time,
                    shares_filled, total_cost_of_fill, price_at_time_of_fill
                ) VALUES (%s, %s, %s, NOW(), %s, %s, %s)
            """, (order_id, account_id, symbol, shares, cost, price))

            connection.commit()
            return order_id

        except (errors.SerializationFailure, errors.DeadlockDetected) as e:
            connection.rollback()
            attempt += 1
            if attempt >= max_retries:
                print(f"❌ Max retries reached: {e}")
                raise
            wait_time = (2 ** attempt) * 0.1 + random.uniform(0, 0.1)
            print(f"⚠️  Retrying after serialization error (attempt {attempt}/{max_retries})")
            time.sleep(wait_time)
        except Exception as e:
            connection.rollback()
            print(f"❌ Error inserting order: {e}")
            raise

def get_row_counts(connection):
    """Get current row counts"""
    cursor = connection.cursor()
    cursor.execute("SELECT COUNT(*) FROM orders")
    orders_count = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM order_fills")
    fills_count = cursor.fetchone()[0]
    return orders_count, fills_count

def run_workload(interval=1, max_orders=None):
    """
    Run continuous workload

    Args:
        interval: Seconds between inserts
        max_orders: Maximum orders to insert (None = infinite)
    """
    print("=" * 60)
    print("🪳 Starting CockroachDB Workload Generator")
    print("=" * 60)
    print(f"📊 Connection: {CRDB_DSN}")
    print(f"⏱️  Interval: {interval} second(s)")
    print(f"🎯 Max orders: {max_orders if max_orders else 'Unlimited'}")
    print("=" * 60)

    connection = get_connection()
    orders_inserted = 0

    try:
        # Show initial counts
        orders_count, fills_count = get_row_counts(connection)
        print(f"📈 Initial counts - Orders: {orders_count}, Fills: {fills_count}")
        print("=" * 60)

        while True:
            # Generate random values
            account_id = 1
            symbol = 'ORCL'
            shares = random.randint(50, 200)
            cost = round(random.uniform(100, 500), 2)

            # Insert order
            order_id = insert_order_with_fill(connection, account_id, symbol, shares, cost)
            orders_inserted += 1

            # Display progress
            timestamp = datetime.now().strftime("%H:%M:%S")
            print(f"✅ [{timestamp}] Order #{order_id} inserted - {shares} shares @ ${cost:.2f}")

            # Check if we've reached max orders
            if max_orders and orders_inserted >= max_orders:
                print(f"\n🎉 Reached max orders ({max_orders}). Stopping workload.")
                break

            # Wait before next insert
            time.sleep(interval)

    except KeyboardInterrupt:
        print("\n\n⏹️  Workload stopped by user")
    except Exception as e:
        print(f"\n\n❌ Workload error: {e}")
    finally:
        # Show final counts
        orders_count, fills_count = get_row_counts(connection)
        print("=" * 60)
        print(f"📊 Final counts - Orders: {orders_count}, Fills: {fills_count}")
        print(f"📈 Inserted {orders_inserted} new orders during this run")
        print("=" * 60)
        connection.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="CockroachDB Workload Generator")
    parser.add_argument("--interval", type=int, default=1,
                       help="Seconds between inserts (default: 1)")
    parser.add_argument("--max-orders", type=int, default=None,
                       help="Maximum orders to insert (default: unlimited)")

    args = parser.parse_args()

    run_workload(interval=args.interval, max_orders=args.max_orders)

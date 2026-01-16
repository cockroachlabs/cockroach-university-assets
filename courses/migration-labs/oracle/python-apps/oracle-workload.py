#!/usr/bin/env python3
"""
Oracle Workload Generator
Continuously inserts orders and order_fills into Oracle database
"""

import time
import random
from datetime import datetime
import argparse

try:
    import oracledb
except ImportError:
    import cx_Oracle as oracledb

# Connection parameters
ORACLE_USER = "APP_USER"
ORACLE_PASSWORD = "apppass"
ORACLE_DSN = "localhost:1521/FREEPDB1"

def get_connection():
    """Create Oracle database connection"""
    try:
        connection = oracledb.connect(
            user=ORACLE_USER,
            password=ORACLE_PASSWORD,
            dsn=ORACLE_DSN
        )
        return connection
    except Exception as e:
        print(f"❌ Error connecting to Oracle: {e}")
        raise

def insert_order_with_fill(connection, account_id=1, symbol='ORCL', shares=100, cost=238.98):
    """
    Insert one order and corresponding order_fill in a transaction
    Triggers will auto-populate order_id and fill_id
    """
    try:
        cursor = connection.cursor()

        # Insert order (trigger will set order_id)
        cursor.execute("""
            INSERT INTO orders (
                account_id, symbol, order_started,
                total_shares_purchased, total_cost_of_order
            ) VALUES (:1, :2, SYSTIMESTAMP, :3, :4)
        """, (account_id, symbol, shares, cost))

        # Get the generated order_id
        cursor.execute("SELECT order_seq.CURRVAL FROM dual")
        order_id = cursor.fetchone()[0]

        # Insert order_fill (trigger will set fill_id)
        price = round(cost / shares, 2)
        cursor.execute("""
            INSERT INTO order_fills (
                order_id, account_id, symbol, fill_time,
                shares_filled, total_cost_of_fill, price_at_time_of_fill
            ) VALUES (:1, :2, :3, SYSTIMESTAMP, :4, :5, :6)
        """, (order_id, account_id, symbol, shares, cost, price))

        connection.commit()
        return order_id

    except Exception as e:
        connection.rollback()
        print(f"⚠️  Error inserting order: {e}")
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
    print("🚀 Starting Oracle Workload Generator")
    print("=" * 60)
    print(f"📊 Connection: {ORACLE_USER}@{ORACLE_DSN}")
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
    parser = argparse.ArgumentParser(description="Oracle Workload Generator")
    parser.add_argument("--interval", type=int, default=1,
                       help="Seconds between inserts (default: 1)")
    parser.add_argument("--max-orders", type=int, default=None,
                       help="Maximum orders to insert (default: unlimited)")

    args = parser.parse_args()

    run_workload(interval=args.interval, max_orders=args.max_orders)

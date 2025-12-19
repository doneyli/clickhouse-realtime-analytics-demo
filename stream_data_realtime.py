#!/usr/bin/env python3
"""
High-Volume Real-time Data Streaming for ClickHouse Demo
Simulates heavy traffic with hundreds of events per second
Perfect for demonstrating ClickHouse's real-time ingestion capabilities
"""

import random
import time
import signal
import sys
from datetime import datetime, timedelta, timezone
from typing import List, Dict
import requests
from faker import Faker
import threading
from concurrent.futures import ThreadPoolExecutor
import uuid

fake = Faker()

# Configuration for HIGH VOLUME streaming
STREAM_INTERVAL = 1  # Insert every 1 second for real-time feel
BATCH_SIZE_EVENTS = 100  # 100 events per second = 360K events/hour!
BATCH_SIZE_ORDERS = 20   # 20 orders per second = 72K orders/hour!
MAX_WORKERS = 4  # Parallel insert threads

# ClickHouse connection settings
CLICKHOUSE_HOST = "localhost"
CLICKHOUSE_PORT = 8123
CLICKHOUSE_USER = "demo_user"
CLICKHOUSE_PASSWORD = "demo_password"
CLICKHOUSE_DB = "demo_db"

class HighVolumeStreamer:
    def __init__(self):
        self.base_url = f"http://{CLICKHOUSE_HOST}:{CLICKHOUSE_PORT}"
        self.auth = (CLICKHOUSE_USER, CLICKHOUSE_PASSWORD)
        self.params = {"database": CLICKHOUSE_DB}
        self.running = True
        self.session_counter = 10000
        self.total_events_inserted = 0
        self.total_orders_inserted = 0
        self.start_time = time.time()

        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)

        print("🚀 ClickHouse HIGH-VOLUME Real-time Data Streamer")
        print("=" * 70)
        print(f"📊 Streaming {BATCH_SIZE_EVENTS} events + {BATCH_SIZE_ORDERS} orders per second")
        print(f"⚡ Target: ~{BATCH_SIZE_EVENTS * 3600:,} events/hour, ~{BATCH_SIZE_ORDERS * 3600:,} orders/hour")
        print(f"🔧 Using {MAX_WORKERS} parallel workers for maximum throughput")
        print("🛑 Press Ctrl+C to stop gracefully")
        print("=" * 70 + "\n")

    def signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        print(f"\n🛑 Received signal {signum}, shutting down gracefully...")
        self.running = False

    def execute_query(self, query: str) -> str:
        """Execute a ClickHouse query"""
        try:
            response = requests.post(
                self.base_url,
                params=self.params,
                data=query,
                auth=self.auth,
                timeout=10
            )
            response.raise_for_status()
            return response.text.strip()
        except Exception as e:
            print(f"❌ Query failed: {e}")
            return ""

    def get_table_count(self, table: str) -> int:
        """Get current row count for a table"""
        try:
            result = self.execute_query(f"SELECT count() FROM {table}")
            return int(result) if result else 0
        except:
            return 0

    def get_user_count(self) -> int:
        """Get total number of users for ID range"""
        return self.get_table_count("users")

    def get_product_count(self) -> int:
        """Get total number of products for ID range"""
        return self.get_table_count("products")

    def generate_events_batch(self, batch_num: int, user_count: int, max_event_id: int) -> List[Dict]:
        """Generate a batch of realistic events"""
        events = []

        event_types = ['page_view', 'click', 'search', 'login', 'logout', 'purchase',
                      'add_to_cart', 'remove_from_cart', 'download', 'signup', 'share']
        device_types = ['desktop', 'mobile', 'tablet']
        browsers = ['Chrome', 'Firefox', 'Safari', 'Edge', 'Opera']
        countries = ['US', 'UK', 'DE', 'FR', 'CA', 'AU', 'JP', 'BR', 'IN', 'RU']
        pages = ['/home', '/products', '/cart', '/checkout', '/profile', '/search',
                '/category/electronics', '/category/books', '/deals', '/about']

        # Simulate realistic user behavior patterns
        # 40% page views, 20% clicks, 15% search, 10% cart actions, 10% purchases, 5% other
        event_weights = {
            'page_view': 0.40,
            'click': 0.20,
            'search': 0.15,
            'add_to_cart': 0.08,
            'purchase': 0.10,
            'remove_from_cart': 0.02,
            'login': 0.02,
            'logout': 0.01,
            'signup': 0.01,
            'share': 0.01
        }

        now = datetime.now(timezone.utc)

        for i in range(BATCH_SIZE_EVENTS):
            event_id = max_event_id + (batch_num * BATCH_SIZE_EVENTS) + i + 1
            user_id = random.randint(1, user_count)

            # Weighted random choice for realistic event distribution
            event_type = random.choices(
                list(event_weights.keys()),
                weights=list(event_weights.values())
            )[0]

            # Generate timestamp within the last second for true "real-time" (UTC)
            event_timestamp = now - timedelta(milliseconds=random.randint(0, 1000))

            session_id = f"sess-{user_id}-{int(now.timestamp() / 300)}"  # 5-min sessions

            revenue = 0
            if event_type == 'purchase':
                revenue = round(random.uniform(20, 500), 2)
            elif event_type == 'add_to_cart':
                # Show potential value in cart
                revenue = round(random.uniform(10, 200), 2) if random.random() < 0.5 else 0

            events.append({
                'event_id': event_id,
                'user_id': user_id,
                'event_type': event_type,
                'event_timestamp': event_timestamp.strftime('%Y-%m-%d %H:%M:%S'),
                'page_url': random.choice(pages) if event_type == 'page_view' else f"/action/{event_type}",
                'session_id': session_id,
                'device_type': random.choice(device_types),
                'browser': random.choice(browsers),
                'country': random.choice(countries),
                'duration_seconds': random.randint(1, 300),
                'revenue': revenue
            })

        return events

    def generate_orders_batch(self, batch_num: int, user_count: int, product_count: int, max_order_id: int) -> List[Dict]:
        """Generate a batch of realistic orders"""
        orders = []

        statuses = ['completed', 'pending', 'cancelled', 'refunded']
        payment_methods = ['credit_card', 'paypal', 'bank_transfer', 'apple_pay', 'google_pay']

        # Realistic status distribution
        status_weights = [0.75, 0.15, 0.07, 0.03]  # Most orders complete successfully

        now = datetime.now(timezone.utc)

        for i in range(BATCH_SIZE_ORDERS):
            order_id = max_order_id + (batch_num * BATCH_SIZE_ORDERS) + i + 1
            user_id = random.randint(1, user_count)
            product_id = random.randint(1, product_count)
            quantity = random.choices([1, 2, 3, 4, 5], weights=[0.5, 0.25, 0.15, 0.07, 0.03])[0]

            # Generate orders within the last second for real-time (UTC)
            order_timestamp = now - timedelta(milliseconds=random.randint(0, 1000))
            order_date = order_timestamp.date()

            status = random.choices(statuses, weights=status_weights)[0]

            # Realistic order values - most between $50-$200, some high value
            if random.random() < 0.9:
                total_amount = round(random.uniform(50, 200), 2)
            else:
                total_amount = round(random.uniform(200, 1000), 2)  # 10% high-value orders

            orders.append({
                'order_id': order_id,
                'user_id': user_id,
                'product_id': product_id,
                'quantity': quantity,
                'order_date': order_date.strftime('%Y-%m-%d'),
                'order_timestamp': order_timestamp.strftime('%Y-%m-%d %H:%M:%S'),
                'total_amount': total_amount,
                'status': status,
                'payment_method': random.choice(payment_methods)
            })

        return orders

    def insert_events(self, events: List[Dict]) -> bool:
        """Insert events using efficient VALUES format"""
        if not events:
            return True

        sql = "INSERT INTO events (event_id, user_id, event_type, event_timestamp, page_url, session_id, device_type, browser, country, duration_seconds, revenue) VALUES "

        values = []
        for event in events:
            values.append(
                f"({event['event_id']}, {event['user_id']}, '{event['event_type']}', "
                f"'{event['event_timestamp']}', '{event['page_url']}', '{event['session_id']}', "
                f"'{event['device_type']}', '{event['browser']}', '{event['country']}', "
                f"{event['duration_seconds']}, {event['revenue']})"
            )

        query = sql + ", ".join(values)
        result = self.execute_query(query)
        success = result == ""

        if success:
            self.total_events_inserted += len(events)

        return success

    def insert_orders(self, orders: List[Dict]) -> bool:
        """Insert orders using efficient VALUES format"""
        if not orders:
            return True

        sql = "INSERT INTO orders (order_id, user_id, product_id, quantity, order_date, order_timestamp, total_amount, status, payment_method) VALUES "

        values = []
        for order in orders:
            values.append(
                f"({order['order_id']}, {order['user_id']}, {order['product_id']}, "
                f"{order['quantity']}, '{order['order_date']}', '{order['order_timestamp']}', "
                f"{order['total_amount']}, '{order['status']}', '{order['payment_method']}')"
            )

        query = sql + ", ".join(values)
        result = self.execute_query(query)
        success = result == ""

        if success:
            self.total_orders_inserted += len(orders)

        return success

    def show_throughput_stats(self):
        """Display real-time throughput statistics"""
        elapsed = time.time() - self.start_time
        events_per_sec = self.total_events_inserted / elapsed if elapsed > 0 else 0
        orders_per_sec = self.total_orders_inserted / elapsed if elapsed > 0 else 0

        print(f"\n📊 THROUGHPUT STATS (Running for {elapsed:.0f}s)")
        print("=" * 70)
        print(f"  Total Events Inserted: {self.total_events_inserted:,}")
        print(f"  Total Orders Inserted: {self.total_orders_inserted:,}")
        print(f"  Events/sec: {events_per_sec:.1f}")
        print(f"  Orders/sec: {orders_per_sec:.1f}")
        print(f"  Projected/hour: {events_per_sec * 3600:,.0f} events, {orders_per_sec * 3600:,.0f} orders")

        # Show database size
        total_events = self.get_table_count("events")
        total_orders = self.get_table_count("orders")
        print(f"\n  Database totals: {total_events:,} events, {total_orders:,} orders")
        print("=" * 70 + "\n")

    def run(self):
        """Main high-volume streaming loop with parallel workers"""
        try:
            # Get initial IDs
            user_count = self.get_user_count()
            product_count = self.get_product_count()

            if user_count == 0 or product_count == 0:
                print("❌ No users or products found. Please run generate_data.py first.")
                return

            print(f"✅ Found {user_count:,} users and {product_count:,} products")
            print(f"🎯 Starting high-volume streaming...\n")

            batch_counter = 0
            stats_interval = 10  # Show stats every 10 seconds
            last_stats_time = time.time()

            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                while self.running:
                    cycle_start = time.time()

                    # Get current max IDs
                    max_event_id = int(self.execute_query("SELECT max(event_id) FROM events") or 0)
                    max_order_id = int(self.execute_query("SELECT max(order_id) FROM orders") or 0)

                    # Generate data
                    events = self.generate_events_batch(batch_counter, user_count, max_event_id)
                    orders = self.generate_orders_batch(batch_counter, user_count, product_count, max_order_id)

                    # Insert in parallel
                    event_future = executor.submit(self.insert_events, events)
                    order_future = executor.submit(self.insert_orders, orders)

                    # Wait for both inserts
                    events_success = event_future.result()
                    orders_success = order_future.result()

                    # Quick status
                    timestamp = datetime.now().strftime('%H:%M:%S')
                    if events_success and orders_success:
                        print(f"⚡ {timestamp} | Batch #{batch_counter:04d} | "
                              f"✅ {BATCH_SIZE_EVENTS} events + {BATCH_SIZE_ORDERS} orders inserted")
                    else:
                        print(f"⚠️  {timestamp} | Batch #{batch_counter:04d} | "
                              f"{'❌ Events' if not events_success else '✅ Events'} | "
                              f"{'❌ Orders' if not orders_success else '✅ Orders'}")

                    batch_counter += 1

                    # Show detailed stats periodically
                    if time.time() - last_stats_time > stats_interval:
                        self.show_throughput_stats()
                        last_stats_time = time.time()

                    # Maintain 1-second interval
                    elapsed = time.time() - cycle_start
                    sleep_time = max(0, STREAM_INTERVAL - elapsed)
                    if sleep_time > 0:
                        time.sleep(sleep_time)

        except KeyboardInterrupt:
            print("\n🛑 Interrupted by user")
        except Exception as e:
            print(f"❌ Unexpected error: {e}")
            import traceback
            traceback.print_exc()
        finally:
            print("\n✅ High-volume streaming stopped")
            self.show_throughput_stats()

def main():
    """Main function"""
    streamer = HighVolumeStreamer()

    # Test connection first
    try:
        result = streamer.execute_query("SELECT 1")
        if result != "1":
            print("❌ Unable to connect to ClickHouse")
            sys.exit(1)
    except Exception as e:
        print(f"❌ Connection test failed: {e}")
        sys.exit(1)

    print("✅ Connected to ClickHouse successfully\n")
    streamer.run()

if __name__ == "__main__":
    main()

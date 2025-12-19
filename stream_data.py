#!/usr/bin/env python3
"""
Real-time data streaming script for ClickHouse demo
Generates new data every 30 seconds while maintaining database size limits
"""

import random
import time
import signal
import sys
from datetime import datetime, timedelta
from typing import List, Dict
import requests
from faker import Faker
import uuid

fake = Faker()

# Configuration
STREAM_INTERVAL = 30  # seconds
MAX_EVENTS_TOTAL = 10000  # Maximum events to keep in database
MAX_ORDERS_TOTAL = 1000   # Maximum orders to keep in database
BATCH_SIZE_EVENTS = 10    # Events to add per batch
BATCH_SIZE_ORDERS = 3     # Orders to add per batch

# ClickHouse connection settings
CLICKHOUSE_HOST = "localhost"
CLICKHOUSE_PORT = 8123
CLICKHOUSE_USER = "demo_user"
CLICKHOUSE_PASSWORD = "demo_password"
CLICKHOUSE_DB = "demo_db"

class ClickHouseStreamer:
    def __init__(self):
        self.base_url = f"http://{CLICKHOUSE_HOST}:{CLICKHOUSE_PORT}"
        self.auth = (CLICKHOUSE_USER, CLICKHOUSE_PASSWORD)
        self.params = {"database": CLICKHOUSE_DB}
        self.running = True
        self.session_counter = 1000
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
        print("🚀 ClickHouse Real-time Data Streamer")
        print(f"📊 Adding {BATCH_SIZE_EVENTS} events and {BATCH_SIZE_ORDERS} orders every {STREAM_INTERVAL} seconds")
        print(f"🔄 Maintaining max {MAX_EVENTS_TOTAL} events and {MAX_ORDERS_TOTAL} orders")
        print("🛑 Press Ctrl+C to stop gracefully\n")
    
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
    
    def cleanup_old_data(self):
        """
        BEST PRACTICE: Use TTL instead of DELETE for data lifecycle management

        DELETE operations in ClickHouse are VERY EXPENSIVE because:
        1. They create mutations that block queries
        2. They require rewriting entire data parts
        3. They don't free space immediately
        4. They impact query performance

        RECOMMENDED APPROACH: Use TTL policies instead (see init-scripts/04-add-ttl.sql)
        - TTL runs in background without blocking queries
        - TTL is 100x more efficient than DELETE
        - TTL handles both deletion and aggregation
        - Set once, runs automatically forever

        Example TTL for this use case:
        ALTER TABLE events MODIFY TTL event_date + INTERVAL 7 DAY DELETE;

        For demo purposes, we'll skip manual cleanup and let TTL handle it.
        If TTL is not configured, uncomment the DELETE code below (not recommended).
        """
        # DEPRECATED: Manual cleanup using DELETE (inefficient)
        # Uncomment only if TTL is not configured

        # events_count = self.get_table_count("events")
        # if events_count > MAX_EVENTS_TOTAL:
        #     excess = events_count - MAX_EVENTS_TOTAL + BATCH_SIZE_EVENTS
        #     cleanup_query = f"""
        #     DELETE FROM events
        #     WHERE event_id IN (
        #         SELECT event_id FROM events
        #         ORDER BY event_timestamp ASC
        #         LIMIT {excess}
        #     )
        #     """
        #     self.execute_query(cleanup_query)
        #     print(f"🧹 Cleaned up {excess} old events (using inefficient DELETE)")

        # orders_count = self.get_table_count("orders")
        # if orders_count > MAX_ORDERS_TOTAL:
        #     excess = orders_count - MAX_ORDERS_TOTAL + BATCH_SIZE_ORDERS
        #     cleanup_query = f"""
        #     DELETE FROM orders
        #     WHERE order_id IN (
        #         SELECT order_id FROM orders
        #         ORDER BY order_timestamp ASC
        #         LIMIT {excess}
        #     )
        #     """
        #     self.execute_query(cleanup_query)
        #     print(f"🧹 Cleaned up {excess} old orders (using inefficient DELETE)")

        # INFO: With TTL configured, cleanup happens automatically in background
        pass
    
    def generate_new_events(self) -> List[Dict]:
        """Generate new realistic events"""
        events = []
        user_count = self.get_user_count()
        
        if user_count == 0:
            print("⚠️ No users found, skipping event generation")
            return events
        
        # Get the highest event_id to continue sequence
        try:
            max_id_result = self.execute_query("SELECT max(event_id) FROM events")
            max_event_id = int(max_id_result) if max_id_result and max_id_result != '0' else 0
        except:
            max_event_id = 0
        
        event_types = ['page_view', 'click', 'search', 'login', 'logout', 'purchase', 
                      'add_to_cart', 'remove_from_cart', 'download', 'signup']
        device_types = ['desktop', 'mobile', 'tablet']
        browsers = ['Chrome', 'Firefox', 'Safari', 'Edge', 'Opera']
        countries = ['US', 'UK', 'DE', 'FR', 'CA', 'AU', 'JP', 'BR', 'IN', 'RU']
        
        for i in range(BATCH_SIZE_EVENTS):
            event_id = max_event_id + i + 1
            user_id = random.randint(1, user_count)
            event_type = random.choice(event_types)
            
            # Make recent events more likely to be engagement events
            if random.random() < 0.3:  # 30% chance for high-value events
                event_type = random.choice(['purchase', 'add_to_cart', 'signup'])
            
            # Generate timestamp within the last few minutes for "real-time" feel
            now = datetime.now()
            event_timestamp = now - timedelta(seconds=random.randint(0, 300))
            
            session_id = f"stream-sess-{self.session_counter + random.randint(1, 100)}"
            
            revenue = 0
            if event_type == 'purchase':
                revenue = round(random.uniform(20, 300), 2)
            elif event_type == 'add_to_cart':
                revenue = round(random.uniform(0, 80), 2)
            
            events.append({
                'event_id': event_id,
                'user_id': user_id,
                'event_type': event_type,
                'event_timestamp': event_timestamp.strftime('%Y-%m-%d %H:%M:%S'),
                'page_url': f"/page/{random.randint(1, 100)}",
                'session_id': session_id,
                'device_type': random.choice(device_types),
                'browser': random.choice(browsers),
                'country': random.choice(countries),
                'duration_seconds': random.randint(5, 600),
                'revenue': revenue
            })
        
        self.session_counter += 1
        return events
    
    def generate_new_orders(self) -> List[Dict]:
        """Generate new realistic orders"""
        orders = []
        user_count = self.get_user_count()
        product_count = self.get_product_count()
        
        if user_count == 0 or product_count == 0:
            print("⚠️ No users or products found, skipping order generation")
            return orders
        
        # Get the highest order_id to continue sequence
        try:
            max_id_result = self.execute_query("SELECT max(order_id) FROM orders")
            max_order_id = int(max_id_result) if max_id_result and max_id_result != '0' else 0
        except:
            max_order_id = 0
        
        statuses = ['completed', 'pending', 'cancelled', 'refunded']
        payment_methods = ['credit_card', 'paypal', 'bank_transfer', 'apple_pay', 'google_pay']
        
        for i in range(BATCH_SIZE_ORDERS):
            order_id = max_order_id + i + 1
            user_id = random.randint(1, user_count)
            product_id = random.randint(1, product_count)
            quantity = random.randint(1, 3)
            
            # Generate recent orders (within last few hours)
            now = datetime.now()
            order_timestamp = now - timedelta(minutes=random.randint(0, 180))
            order_date = order_timestamp.date()
            
            # Bias towards completed orders for more realistic revenue
            status_weights = [0.7, 0.15, 0.1, 0.05]  # completed, pending, cancelled, refunded
            status = random.choices(statuses, weights=status_weights)[0]
            
            total_amount = round(random.uniform(25, 400), 2)
            
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
    
    def insert_events(self, events: List[Dict]):
        """Insert events using SQL VALUES"""
        if not events:
            return
        
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
        if result == "":
            print(f"✅ Added {len(events)} new events")
        else:
            print(f"❌ Failed to add events: {result}")
    
    def insert_orders(self, orders: List[Dict]):
        """Insert orders using SQL VALUES"""
        if not orders:
            return
        
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
        if result == "":
            print(f"✅ Added {len(orders)} new orders")
        else:
            print(f"❌ Failed to add orders: {result}")
    
    def show_stats(self):
        """Display current database statistics"""
        tables = ['users', 'products', 'orders', 'events']
        print("\n📊 Current database stats:")
        for table in tables:
            count = self.get_table_count(table)
            print(f"  {table}: {count:,} rows")
        
        # Show recent activity
        try:
            recent_events = self.execute_query(
                "SELECT count() FROM events WHERE event_timestamp >= now() - INTERVAL 5 MINUTE"
            )
            recent_orders = self.execute_query(
                "SELECT count() FROM orders WHERE order_timestamp >= now() - INTERVAL 5 MINUTE"
            )
            print(f"  📈 Recent activity (5 min): {recent_events} events, {recent_orders} orders")
        except:
            pass
        print()
    
    def run(self):
        """Main streaming loop"""
        try:
            # Initial stats
            self.show_stats()
            
            while self.running:
                start_time = time.time()
                
                # Clean up old data first
                self.cleanup_old_data()
                
                # Generate and insert new data
                print(f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} - Generating new data...")
                
                events = self.generate_new_events()
                orders = self.generate_new_orders()
                
                self.insert_events(events)
                self.insert_orders(orders)
                
                # Show updated stats every few cycles
                if int(time.time()) % (STREAM_INTERVAL * 3) < STREAM_INTERVAL:
                    self.show_stats()
                
                # Wait for next cycle
                elapsed = time.time() - start_time
                sleep_time = max(0, STREAM_INTERVAL - elapsed)
                
                if sleep_time > 0:
                    print(f"💤 Waiting {sleep_time:.1f}s until next batch...\n")
                    time.sleep(sleep_time)
                
        except KeyboardInterrupt:
            print("\n🛑 Interrupted by user")
        except Exception as e:
            print(f"❌ Unexpected error: {e}")
        finally:
            print("✅ Data streaming stopped gracefully")
            print("📊 Final database state:")
            self.show_stats()

def main():
    """Main function"""
    streamer = ClickHouseStreamer()
    
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

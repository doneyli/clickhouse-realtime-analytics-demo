#!/usr/bin/env python3
"""
Interactive Real-Time Analytics Dashboard for ClickHouse Demo
Customer-facing application with live updates and interactive visualizations
"""

from flask import Flask, render_template, jsonify, Response, request
from clickhouse_driver import Client
import json
import time
from datetime import datetime, timedelta
import os

app = Flask(__name__, template_folder='templates_interactive', static_folder='static_interactive')

# ClickHouse connection settings
CLICKHOUSE_HOST = os.environ.get('CLICKHOUSE_HOST', 'localhost')
CLICKHOUSE_PORT = int(os.environ.get('CLICKHOUSE_PORT', 9000))
CLICKHOUSE_USER = os.environ.get('CLICKHOUSE_USER', 'demo_user')
CLICKHOUSE_PASSWORD = os.environ.get('CLICKHOUSE_PASSWORD', 'demo_password')
CLICKHOUSE_DB = os.environ.get('CLICKHOUSE_DB', 'demo_db')

def get_clickhouse_client():
    """Create and return a ClickHouse client"""
    return Client(
        host=CLICKHOUSE_HOST,
        port=CLICKHOUSE_PORT,
        user=CLICKHOUSE_USER,
        password=CLICKHOUSE_PASSWORD,
        database=CLICKHOUSE_DB
    )

@app.route('/')
def index():
    """Main interactive dashboard page"""
    return render_template('interactive_dashboard.html')

@app.route('/api/live/events-stream')
def events_stream():
    """Server-Sent Events endpoint for real-time event stream"""
    def generate():
        client = get_clickhouse_client()
        last_event_id = 0

        while True:
            try:
                # Get latest events since last check
                query = f"""
                SELECT
                    event_id,
                    user_id,
                    event_type,
                    event_timestamp,
                    country,
                    device_type,
                    browser,
                    revenue
                FROM events
                WHERE event_id > {last_event_id}
                ORDER BY event_id ASC
                LIMIT 50
                """

                results = client.execute(query)

                if results:
                    events = []
                    for row in results:
                        events.append({
                            'event_id': row[0],
                            'user_id': row[1],
                            'event_type': row[2],
                            'event_timestamp': row[3].strftime('%Y-%m-%d %H:%M:%S') if hasattr(row[3], 'strftime') else str(row[3]),
                            'country': row[4],
                            'device_type': row[5],
                            'browser': row[6],
                            'revenue': float(row[7]) if row[7] else 0
                        })
                        last_event_id = max(last_event_id, row[0])

                    yield f"data: {json.dumps(events)}\n\n"

                time.sleep(1)  # Poll every second

            except Exception as e:
                yield f"data: {json.dumps({'error': str(e)})}\n\n"
                time.sleep(2)

    return Response(generate(), mimetype='text/event-stream')

@app.route('/api/live/metrics')
def live_metrics():
    """Get current real-time metrics"""
    client = get_clickhouse_client()

    try:
        # Get metrics for last 1 minute, last 5 minutes, last hour
        query = """
        SELECT
            'last_1min' as period,
            count() as events,
            uniq(user_id) as unique_users,
            countIf(event_type = 'purchase') as purchases,
            sumIf(revenue, event_type = 'purchase') as revenue
        FROM events
        WHERE event_timestamp >= now() - INTERVAL 1 MINUTE

        UNION ALL

        SELECT
            'last_5min' as period,
            count() as events,
            uniq(user_id) as unique_users,
            countIf(event_type = 'purchase') as purchases,
            sumIf(revenue, event_type = 'purchase') as revenue
        FROM events
        WHERE event_timestamp >= now() - INTERVAL 5 MINUTE

        UNION ALL

        SELECT
            'last_1hour' as period,
            count() as events,
            uniq(user_id) as unique_users,
            countIf(event_type = 'purchase') as purchases,
            sumIf(revenue, event_type = 'purchase') as revenue
        FROM events
        WHERE event_timestamp >= now() - INTERVAL 1 HOUR
        """

        results = client.execute(query)

        metrics = {}
        for row in results:
            metrics[row[0]] = {
                'events': row[1],
                'unique_users': row[2],
                'purchases': row[3],
                'revenue': float(row[4]) if row[4] else 0
            }

        # Add events per second calculation
        if 'last_1min' in metrics:
            metrics['events_per_second'] = round(metrics['last_1min']['events'] / 60.0, 2)

        return jsonify(metrics)

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/live/event-types')
def live_event_types():
    """Get real-time event type distribution"""
    client = get_clickhouse_client()

    try:
        query = """
        SELECT
            event_type,
            count() as event_count,
            round(count() * 100.0 / sum(count()) OVER (), 2) as percentage
        FROM events
        WHERE event_timestamp >= now() - INTERVAL 5 MINUTE
        GROUP BY event_type
        ORDER BY event_count DESC
        """

        results = client.execute(query)

        data = []
        for row in results:
            data.append({
                'event_type': row[0],
                'count': row[1],
                'percentage': float(row[2])
            })

        return jsonify(data)

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/live/geographic')
def live_geographic():
    """Get real-time geographic distribution"""
    client = get_clickhouse_client()

    try:
        query = """
        SELECT
            country,
            count() as events,
            uniq(user_id) as users,
            sumIf(revenue, event_type = 'purchase') as revenue
        FROM events
        WHERE event_timestamp >= now() - INTERVAL 5 MINUTE
        GROUP BY country
        ORDER BY events DESC
        LIMIT 10
        """

        results = client.execute(query)

        data = []
        for row in results:
            data.append({
                'country': row[0],
                'events': row[1],
                'users': row[2],
                'revenue': float(row[3]) if row[3] else 0
            })

        return jsonify(data)

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/live/timeline')
def live_timeline():
    """Get events timeline for last 30 minutes (by minute)"""
    client = get_clickhouse_client()

    try:
        query = """
        SELECT
            toStartOfMinute(event_timestamp) as minute,
            count() as events,
            uniq(user_id) as unique_users,
            countIf(event_type = 'purchase') as purchases
        FROM events
        WHERE event_timestamp >= now() - INTERVAL 30 MINUTE
        GROUP BY minute
        ORDER BY minute ASC
        """

        results = client.execute(query)

        data = {
            'timestamps': [],
            'events': [],
            'users': [],
            'purchases': []
        }

        for row in results:
            data['timestamps'].append(row[0].strftime('%H:%M') if hasattr(row[0], 'strftime') else str(row[0]))
            data['events'].append(row[1])
            data['users'].append(row[2])
            data['purchases'].append(row[3])

        return jsonify(data)

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/query/execute', methods=['POST'])
def execute_custom_query():
    """Execute a custom ClickHouse query (read-only)"""
    client = get_clickhouse_client()

    try:
        data = request.get_json()
        query = data.get('query', '').strip()

        if not query:
            return jsonify({'error': 'No query provided'}), 400

        # Basic security: only allow SELECT queries
        query_upper = query.upper().strip()
        if not query_upper.startswith('SELECT') and not query_upper.startswith('SHOW') and not query_upper.startswith('DESCRIBE'):
            return jsonify({'error': 'Only SELECT, SHOW, and DESCRIBE queries are allowed'}), 403

        # Block dangerous keywords
        dangerous_keywords = ['DROP', 'DELETE', 'INSERT', 'UPDATE', 'ALTER', 'CREATE', 'TRUNCATE']
        if any(keyword in query_upper for keyword in dangerous_keywords):
            return jsonify({'error': 'Query contains forbidden keywords'}), 403

        # Execute query
        start_time = time.time()
        results = client.execute(query)
        execution_time = time.time() - start_time

        # Convert results to JSON-serializable format
        rows = []
        for row in results:
            serialized_row = []
            for value in row:
                if hasattr(value, 'strftime'):
                    serialized_row.append(value.strftime('%Y-%m-%d %H:%M:%S'))
                elif isinstance(value, (int, float, str, bool, type(None))):
                    serialized_row.append(value)
                else:
                    serialized_row.append(str(value))
            rows.append(serialized_row)

        return jsonify({
            'success': True,
            'rows': rows,
            'row_count': len(rows),
            'execution_time': round(execution_time * 1000, 2)  # ms
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/live/top-users')
def live_top_users():
    """Get most active users in last 5 minutes"""
    client = get_clickhouse_client()

    try:
        query = """
        SELECT
            user_id,
            count() as event_count,
            uniq(event_type) as event_types,
            sum(revenue) as total_revenue,
            max(event_timestamp) as last_seen
        FROM events
        WHERE event_timestamp >= now() - INTERVAL 5 MINUTE
        GROUP BY user_id
        ORDER BY event_count DESC
        LIMIT 10
        """

        results = client.execute(query)

        data = []
        for row in results:
            data.append({
                'user_id': row[0],
                'event_count': row[1],
                'event_types': row[2],
                'total_revenue': float(row[3]) if row[3] else 0,
                'last_seen': row[4].strftime('%H:%M:%S') if hasattr(row[4], 'strftime') else str(row[4])
            })

        return jsonify(data)

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/live/conversion-rate')
def live_conversion_rate():
    """Get real-time conversion metrics"""
    client = get_clickhouse_client()

    try:
        query = """
        SELECT
            countIf(event_type = 'page_view') as page_views,
            countIf(event_type = 'add_to_cart') as cart_adds,
            countIf(event_type = 'purchase') as purchases,
            round(countIf(event_type = 'add_to_cart') * 100.0 / nullIf(countIf(event_type = 'page_view'), 0), 2) as cart_rate,
            round(countIf(event_type = 'purchase') * 100.0 / nullIf(countIf(event_type = 'add_to_cart'), 0), 2) as purchase_rate,
            round(countIf(event_type = 'purchase') * 100.0 / nullIf(countIf(event_type = 'page_view'), 0), 2) as overall_conversion
        FROM events
        WHERE event_timestamp >= now() - INTERVAL 5 MINUTE
        """

        results = client.execute(query)

        if results:
            row = results[0]
            return jsonify({
                'page_views': row[0],
                'cart_adds': row[1],
                'purchases': row[2],
                'cart_rate': float(row[3]) if row[3] else 0,
                'purchase_rate': float(row[4]) if row[4] else 0,
                'overall_conversion': float(row[5]) if row[5] else 0
            })

        return jsonify({})

    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    print("🚀 Starting Interactive Real-Time Analytics Dashboard")
    print("=" * 70)
    print("📊 Dashboard URL: http://localhost:3001")
    print("⚡ Real-time updates enabled via Server-Sent Events")
    print("🔍 Interactive query builder available")
    print("=" * 70 + "\n")

    app.run(host='0.0.0.0', port=3001, debug=True)

#!/usr/bin/env python3
"""
ClickHouse Demo Web Application
A Flask-based dashboard for exploring ClickHouse analytics
"""

import os
from flask import Flask, render_template, jsonify, request
from clickhouse_driver import Client
import pandas as pd
import plotly.graph_objs as go
import plotly.utils
import json
from datetime import datetime, timedelta

app = Flask(__name__)

# ClickHouse connection settings
CLICKHOUSE_HOST = os.getenv('CLICKHOUSE_HOST', 'localhost')
CLICKHOUSE_PORT = int(os.getenv('CLICKHOUSE_PORT', '9000'))
CLICKHOUSE_USER = os.getenv('CLICKHOUSE_USER', 'demo_user')
CLICKHOUSE_PASSWORD = os.getenv('CLICKHOUSE_PASSWORD', 'demo_password')
CLICKHOUSE_DB = os.getenv('CLICKHOUSE_DB', 'demo_db')

# Initialize ClickHouse client
def get_clickhouse_client():
    return Client(
        host=CLICKHOUSE_HOST,
        port=CLICKHOUSE_PORT,
        user=CLICKHOUSE_USER,
        password=CLICKHOUSE_PASSWORD,
        database=CLICKHOUSE_DB
    )

@app.route('/')
def dashboard():
    """Main dashboard page"""
    return render_template('dashboard.html')

@app.route('/api/stats')
def get_stats():
    """Get basic statistics about the database"""
    client = get_clickhouse_client()
    
    try:
        # Get table counts
        stats = {}
        tables = ['users', 'events', 'products', 'orders']
        
        for table in tables:
            count = client.execute(f"SELECT count() FROM {table}")[0][0]
            stats[f'{table}_count'] = count
        
        # Get additional metrics
        # Active users in last 30 days
        active_users = client.execute("""
            SELECT uniq(user_id) 
            FROM events 
            WHERE event_timestamp >= now() - INTERVAL 30 DAY
        """)[0][0]
        stats['active_users_30d'] = active_users
        
        # Total revenue
        total_revenue = client.execute("""
            SELECT sum(total_amount) 
            FROM orders 
            WHERE status = 'completed'
        """)[0][0] or 0
        stats['total_revenue'] = float(total_revenue)
        
        # Average order value
        avg_order_value = client.execute("""
            SELECT avg(total_amount) 
            FROM orders 
            WHERE status = 'completed'
        """)[0][0] or 0
        stats['avg_order_value'] = float(avg_order_value)
        
        return jsonify(stats)
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/daily-events')
def get_daily_events():
    """Get daily event counts for the last 30 days"""
    client = get_clickhouse_client()
    
    try:
        query = """
        SELECT 
            toDate(event_timestamp) as date,
            count() as events,
            uniq(user_id) as unique_users
        FROM events 
        WHERE event_timestamp >= now() - INTERVAL 30 DAY
        GROUP BY date 
        ORDER BY date
        """
        
        results = client.execute(query)
        data = {
            'dates': [row[0].strftime('%Y-%m-%d') for row in results],
            'events': [row[1] for row in results],
            'unique_users': [row[2] for row in results]
        }
        
        return jsonify(data)
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/event-types')
def get_event_types():
    """Get event type distribution"""
    client = get_clickhouse_client()
    
    try:
        query = """
        SELECT 
            event_type,
            count() as count
        FROM events 
        WHERE event_timestamp >= now() - INTERVAL 7 DAY
        GROUP BY event_type 
        ORDER BY count DESC
        """
        
        results = client.execute(query)
        data = {
            'labels': [row[0] for row in results],
            'values': [row[1] for row in results]
        }
        
        return jsonify(data)
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/top-countries')
def get_top_countries():
    """Get top countries by user count"""
    client = get_clickhouse_client()
    
    try:
        query = """
        SELECT 
            country,
            count() as user_count,
            avg(age) as avg_age,
            sum(total_spent) as total_spent
        FROM users 
        GROUP BY country 
        ORDER BY user_count DESC 
        LIMIT 10
        """
        
        results = client.execute(query)
        data = []
        for row in results:
            data.append({
                'country': row[0],
                'user_count': row[1],
                'avg_age': round(float(row[2]), 1),
                'total_spent': float(row[3])
            })
        
        return jsonify(data)
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/revenue-by-month')
def get_revenue_by_month():
    """Get monthly revenue for the last 12 months"""
    client = get_clickhouse_client()
    
    try:
        query = """
        SELECT 
            toYYYYMM(order_date) as month,
            sum(total_amount) as revenue,
            count() as order_count
        FROM orders 
        WHERE status = 'completed' 
        AND order_date >= today() - INTERVAL 12 MONTH
        GROUP BY month 
        ORDER BY month
        """
        
        results = client.execute(query)
        data = {
            'months': [str(row[0]) for row in results],
            'revenue': [float(row[1]) for row in results],
            'orders': [row[2] for row in results]
        }
        
        return jsonify(data)
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/top-products')
def get_top_products():
    """Get top-selling products using materialized view"""
    client = get_clickhouse_client()

    try:
        # Use materialized view instead of JOIN - much faster!
        query = """
        SELECT
            p.product_name,
            p.category,
            p.price,
            sum(mv.total_quantity) as total_sold,
            sum(mv.total_revenue) as total_revenue
        FROM mv_product_revenue mv
        JOIN products p ON mv.product_id = p.product_id
        WHERE mv.status = 'completed'
        GROUP BY p.product_id, p.product_name, p.category, p.price
        ORDER BY total_sold DESC
        LIMIT 20
        """

        results = client.execute(query)
        data = []
        for row in results:
            data.append({
                'product_name': row[0],
                'category': row[1],
                'price': float(row[2]),
                'total_sold': row[3],
                'total_revenue': float(row[4])
            })

        return jsonify(data)

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/user-segments')
def get_user_segments():
    """Get user segments by activity and spending"""
    client = get_clickhouse_client()
    
    try:
        query = """
        SELECT 
            CASE 
                WHEN total_spent >= 1000 THEN 'High Value'
                WHEN total_spent >= 500 THEN 'Medium Value'
                WHEN total_spent >= 100 THEN 'Low Value'
                ELSE 'New Customer'
            END as segment,
            count() as user_count,
            avg(total_spent) as avg_spent,
            avg(age) as avg_age
        FROM users 
        GROUP BY segment
        ORDER BY avg_spent DESC
        """
        
        results = client.execute(query)
        data = []
        for row in results:
            data.append({
                'segment': row[0],
                'user_count': row[1],
                'avg_spent': round(float(row[2]), 2),
                'avg_age': round(float(row[3]), 1)
            })
        
        return jsonify(data)
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/conversion-funnel')
def get_conversion_funnel():
    """Get conversion funnel metrics using materialized view"""
    client = get_clickhouse_client()

    try:
        # Query the funnel MV with AggregatingMergeTree functions
        # Use CTE to compute merged aggregates first, then calculate ratios
        query = """
        WITH agg AS (
            SELECT
                countMerge(total_events) as total_events,
                sumMerge(page_views) as page_views,
                sumMerge(cart_adds) as cart_adds,
                sumMerge(purchases) as purchases,
                sumMerge(total_revenue) as revenue
            FROM mv_user_funnel
            WHERE event_date >= today() - INTERVAL 30 DAY
        )
        SELECT
            total_events,
            page_views,
            cart_adds,
            purchases,
            revenue,
            round(purchases * 100.0 / page_views, 2) as conversion_rate,
            round(cart_adds * 100.0 / page_views, 2) as cart_add_rate
        FROM agg
        """

        results = client.execute(query)
        if results:
            row = results[0]
            data = {
                'total_events': row[0],
                'page_views': row[1],
                'cart_adds': row[2],
                'purchases': row[3],
                'revenue': float(row[4]),
                'conversion_rate': float(row[5]),
                'cart_add_rate': float(row[6])
            }
        else:
            data = {}

        return jsonify(data)

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/hourly-activity')
def get_hourly_activity():
    """Get hourly activity trends using materialized view"""
    client = get_clickhouse_client()

    try:
        # Query hourly aggregations - much faster than scanning raw events
        query = """
        SELECT
            event_hour,
            sum(event_count) as total_events,
            sum(unique_users) as unique_users,
            sum(total_revenue) as revenue
        FROM mv_hourly_events
        WHERE event_date >= today() - INTERVAL 7 DAY
        GROUP BY event_hour
        ORDER BY event_hour
        """

        results = client.execute(query)
        data = {
            'hours': [row[0] for row in results],
            'events': [row[1] for row in results],
            'users': [row[2] for row in results],
            'revenue': [float(row[3]) for row in results]
        }

        return jsonify(data)

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/search')
def search():
    """Search functionality for exploring data"""
    query_type = request.args.get('type', 'users')
    search_term = request.args.get('q', '')
    limit = int(request.args.get('limit', 50))
    
    client = get_clickhouse_client()
    
    try:
        if query_type == 'users':
            query = f"""
            SELECT user_id, username, email, country, age, total_spent, registration_date
            FROM users 
            WHERE username ILIKE '%{search_term}%' OR email ILIKE '%{search_term}%'
            ORDER BY total_spent DESC
            LIMIT {limit}
            """
        elif query_type == 'products':
            query = f"""
            SELECT product_id, product_name, category, price, created_date
            FROM products 
            WHERE product_name ILIKE '%{search_term}%' OR category ILIKE '%{search_term}%'
            ORDER BY price DESC
            LIMIT {limit}
            """
        else:
            return jsonify({'error': 'Invalid query type'}), 400
        
        results = client.execute(query)
        
        if query_type == 'users':
            data = [{
                'user_id': row[0],
                'username': row[1],
                'email': row[2],
                'country': row[3],
                'age': row[4],
                'total_spent': float(row[5]),
                'registration_date': row[6].strftime('%Y-%m-%d')
            } for row in results]
        else:
            data = [{
                'product_id': row[0],
                'product_name': row[1],
                'category': row[2],
                'price': float(row[3]),
                'created_date': row[4].strftime('%Y-%m-%d')
            } for row in results]
        
        return jsonify(data)
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    import logging
    logging.basicConfig(level=logging.DEBUG)
    app.run(host='0.0.0.0', port=3000, debug=True)

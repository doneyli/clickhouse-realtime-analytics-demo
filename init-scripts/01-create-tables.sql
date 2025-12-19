-- Create database
CREATE DATABASE IF NOT EXISTS demo_db;

-- Switch to demo database
USE demo_db;

-- ============================================================================
-- OPTIMIZED TABLE SCHEMAS WITH BEST PRACTICES
-- ============================================================================
-- Features showcased:
-- - LowCardinality for string columns with limited distinct values
-- - Compression codecs (Delta, T64, ZSTD) for reduced storage
-- - Optimized ORDER BY based on actual query patterns
-- - Proper data types (UUID, FixedString)
-- - ALIAS columns for computed values
-- - Efficient partitioning strategies
-- ============================================================================

-- Create users table with optimized schema
CREATE TABLE IF NOT EXISTS users (
    user_id UInt64,
    username String,
    email String,
    age UInt8 CODEC(T64, ZSTD(1)),
    country LowCardinality(String),  -- Low cardinality optimization
    registration_date Date CODEC(Delta, ZSTD(1)),
    registration_timestamp DateTime CODEC(Delta, ZSTD(3)),
    is_premium UInt8,
    total_spent Decimal(10,2) CODEC(ZSTD(1))
) ENGINE = MergeTree()
ORDER BY (country, is_premium, user_id)  -- Optimized for country/premium filtering
SETTINGS index_granularity = 8192;

-- Create events table with advanced optimizations
CREATE TABLE IF NOT EXISTS events (
    event_id UInt64,
    user_id UInt64,
    event_type LowCardinality(String),  -- Low cardinality optimization
    event_timestamp DateTime CODEC(Delta, ZSTD(3)),  -- Delta encoding for timestamps
    event_date Date MATERIALIZED toDate(event_timestamp),
    event_hour UInt8 ALIAS toHour(event_timestamp),  -- ALIAS for computed column
    page_url String,
    session_id String,  -- Keep as String for compatibility with existing data
    device_type LowCardinality(String),
    browser LowCardinality(String),
    country LowCardinality(String),
    duration_seconds UInt32 CODEC(T64, ZSTD(1)),  -- T64 for integers
    revenue Decimal(10,2) DEFAULT 0 CODEC(ZSTD(1))
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)  -- Monthly partitions for better management
ORDER BY (event_type, event_date, user_id, event_timestamp)  -- Optimized for event_type filtering
SETTINGS index_granularity = 8192;

-- Create products table with optimizations
CREATE TABLE IF NOT EXISTS products (
    product_id UInt64,
    product_name String,
    category LowCardinality(String),  -- Low cardinality optimization
    price Decimal(10,2) CODEC(ZSTD(1)),
    created_date Date CODEC(Delta, ZSTD(1)),
    is_active UInt8
) ENGINE = MergeTree()
ORDER BY (category, product_id)  -- Optimized for category grouping
SETTINGS index_granularity = 8192;

-- Create orders table with optimized schema
CREATE TABLE IF NOT EXISTS orders (
    order_id UInt64,
    user_id UInt64,
    product_id UInt64,
    quantity UInt32 CODEC(T64, ZSTD(1)),
    order_date Date CODEC(Delta, ZSTD(1)),
    order_timestamp DateTime CODEC(Delta, ZSTD(3)),
    total_amount Decimal(10,2) CODEC(ZSTD(1)),
    status LowCardinality(String),  -- Low cardinality optimization
    payment_method LowCardinality(String)  -- Low cardinality optimization
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)  -- Monthly partitions
ORDER BY (status, order_date, user_id, order_timestamp)  -- Optimized for status filtering
SETTINGS index_granularity = 8192;

-- ============================================================================
-- MATERIALIZED VIEWS FOR REAL-TIME ANALYTICS
-- ============================================================================

-- Create materialized view for daily user activity summary
CREATE MATERIALIZED VIEW IF NOT EXISTS daily_user_activity
ENGINE = SummingMergeTree()
ORDER BY (event_date, user_id)
AS SELECT
    event_date,
    user_id,
    count() as total_events,
    sum(duration_seconds) as total_duration,
    sum(revenue) as total_revenue,
    uniq(session_id) as unique_sessions
FROM events
GROUP BY event_date, user_id;

-- Create materialized view for product revenue analytics
-- Eliminates JOINs at query time for product performance queries
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_product_revenue
ENGINE = SummingMergeTree()
ORDER BY (product_id, order_date, status)
POPULATE  -- Backfill existing data
AS SELECT
    product_id,
    toDate(order_timestamp) as order_date,
    status,
    count() as order_count,
    sum(total_amount) as total_revenue,
    sum(quantity) as total_quantity,
    avg(total_amount) as avg_order_value
FROM orders
GROUP BY product_id, order_date, status;

-- Create materialized view for user conversion funnel
-- Tracks user journey from page_view → add_to_cart → purchase
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_funnel
ENGINE = AggregatingMergeTree()
ORDER BY (user_id, event_date)
POPULATE
AS SELECT
    user_id,
    event_date,
    countState() as total_events,
    sumState(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) as page_views,
    sumState(CASE WHEN event_type = 'add_to_cart' THEN 1 ELSE 0 END) as cart_adds,
    sumState(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) as purchases,
    sumState(revenue) as total_revenue
FROM events
GROUP BY user_id, event_date;

-- Create materialized view for hourly event aggregation
-- Enables real-time dashboard with minimal latency
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_hourly_events
ENGINE = SummingMergeTree()
ORDER BY (event_date, event_hour, event_type, country)
POPULATE
AS SELECT
    event_date,
    toHour(event_timestamp) as event_hour,
    event_type,
    device_type,
    country,
    count() as event_count,
    uniq(user_id) as unique_users,
    sum(duration_seconds) as total_duration,
    avg(duration_seconds) as avg_duration,
    sum(revenue) as total_revenue
FROM events
GROUP BY event_date, event_hour, event_type, device_type, country;

-- Create materialized view for country-level analytics
-- Pre-aggregated for geographic reporting
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_country_stats
ENGINE = SummingMergeTree()
ORDER BY (country, event_date)
POPULATE
AS SELECT
    country,
    event_date,
    event_type,
    count() as event_count,
    uniq(user_id) as unique_users,
    sum(revenue) as total_revenue
FROM events
GROUP BY country, event_date, event_type;

-- Create view for user analytics (regular view for flexible queries)
CREATE VIEW IF NOT EXISTS user_analytics AS
SELECT
    u.user_id,
    u.username,
    u.country,
    u.age,
    u.is_premium,
    u.total_spent,
    u.registration_date,
    count(e.event_id) as total_events,
    count(DISTINCT e.session_id) as unique_sessions,
    sum(e.duration_seconds) as total_time_spent,
    count(DISTINCT e.event_date) as active_days,
    avg(e.duration_seconds) as avg_session_duration
FROM users u
LEFT JOIN events e ON u.user_id = e.user_id
GROUP BY u.user_id, u.username, u.country, u.age, u.is_premium, u.total_spent, u.registration_date;

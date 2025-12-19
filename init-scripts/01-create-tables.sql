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

-- Create view for user analytics
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

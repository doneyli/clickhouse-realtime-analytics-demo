-- ============================================================================
-- TTL (TIME TO LIVE) POLICIES FOR AUTOMATIC DATA LIFECYCLE MANAGEMENT
-- ============================================================================
-- TTL enables automatic data deletion, aggregation, or movement based on time
-- Much more efficient than DELETE queries which are expensive in ClickHouse
-- ============================================================================

USE demo_db;

-- ============================================================================
-- EVENTS TABLE TTL POLICIES
-- ============================================================================

-- Strategy 1: Delete old detailed events after 90 days
-- For demo purposes, we'll use shorter TTL to show the concept
-- Uncomment the appropriate policy based on your needs:

-- Option A: Simple deletion after 90 days (production recommended)
-- ALTER TABLE events MODIFY TTL event_date + INTERVAL 90 DAY DELETE;

-- Option B: For demo - keep only last 7 days of detailed events
-- ALTER TABLE events MODIFY TTL event_date + INTERVAL 7 DAY DELETE;

-- Option C: Simple deletion after 90 days (for demo compatibility)
-- Note: Hierarchical TTL requires GROUP BY to match primary key prefix
-- Since our ORDER BY is (event_type, event_date, user_id, event_timestamp),
-- we use simple deletion here. For production with custom ORDER BY for TTL,
-- design the primary key to support your TTL GROUP BY strategy.
ALTER TABLE events MODIFY TTL event_date + INTERVAL 90 DAY DELETE;

-- ============================================================================
-- ORDERS TABLE TTL POLICIES
-- ============================================================================

-- Keep completed orders for 2 years, then archive to cold storage
-- For demo: Keep orders for 1 year
ALTER TABLE orders MODIFY TTL
    order_date + INTERVAL 1 YEAR DELETE;

-- Alternative: Move old orders to cold storage instead of deleting
-- Requires setting up storage policies in ClickHouse config
-- ALTER TABLE orders MODIFY TTL
--     order_date + INTERVAL 6 MONTH TO DISK 'cold_storage',
--     order_date + INTERVAL 2 YEAR DELETE;

-- ============================================================================
-- MATERIALIZED VIEW TTL POLICIES
-- ============================================================================
-- Note: TTL is applied to the destination table of the MV, not the MV itself
-- MaterializedViews are just SELECT queries; the data is stored in underlying tables
--
-- For MVs created with ENGINE = SummingMergeTree/AggregatingMergeTree,
-- we can set TTL on those target tables.
--
-- The source table's TTL (events, orders) controls when source data expires.
-- MV's target table TTL controls when aggregated data expires.
--
-- For this demo, we'll set TTL on target tables of our MVs:
--
-- Note: daily_user_activity, mv_hourly_events, mv_product_revenue, mv_user_funnel,
-- and mv_country_stats are MaterializedViews. To set TTL, we need to specify it
-- during table creation in 01-create-tables.sql, or we can modify the .inner table
-- that ClickHouse automatically creates.
--
-- For this demo setup, we'll skip MV TTL to avoid errors.
-- In production, define TTL in the ENGINE clause during MV creation:
--
-- Example:
-- CREATE MATERIALIZED VIEW mv_hourly_events
-- ENGINE = SummingMergeTree()
-- ORDER BY (event_date, event_hour)
-- TTL event_date + INTERVAL 90 DAY DELETE
-- AS SELECT ...
--
-- Since our MVs are already created without TTL in the ENGINE clause,
-- we cannot modify them here. This is a design consideration for your schema.

-- ============================================================================
-- TTL FOR SPECIFIC COLUMNS (OPTIONAL)
-- ============================================================================
-- You can also set TTL on individual columns to NULL them after time
-- Useful for GDPR/privacy compliance

-- Example: Remove PII after 90 days while keeping aggregated data
-- ALTER TABLE users MODIFY COLUMN email String TTL registration_date + INTERVAL 90 DAY;
-- ALTER TABLE users MODIFY COLUMN username String TTL registration_date + INTERVAL 90 DAY;

-- ============================================================================
-- BENEFITS OF TTL vs DELETE
-- ============================================================================
-- 1. Performance: TTL runs in background, DELETE blocks queries
-- 2. Efficiency: TTL operates on entire parts, DELETE requires mutations
-- 3. Automatic: Set once, runs forever - no cron jobs needed
-- 4. Flexible: Can delete, aggregate, or move data
-- 5. Graceful: Doesn't impact query performance
--
-- For demo streaming: Instead of DELETE FROM events WHERE...,
-- use TTL to automatically maintain size limits
-- ============================================================================

-- ============================================================================
-- CHECK TTL SETTINGS
-- ============================================================================
-- To see TTL configuration for a table:
-- SELECT name, engine, create_table_query FROM system.tables WHERE name = 'events';
--
-- To check when TTL will run next:
-- SELECT * FROM system.parts WHERE table = 'events' AND active;
-- Look at the 'ttl_info' column
-- ============================================================================

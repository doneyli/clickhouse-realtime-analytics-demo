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

-- Option C: Hierarchical TTL - aggregate old data before deleting
-- Keep detailed data for 30 days, then aggregate, then delete after 90 days
ALTER TABLE events MODIFY TTL
    -- Keep detailed events for 30 days
    event_date + INTERVAL 30 DAY,
    -- After 30 days, aggregate to hourly granularity
    event_date + INTERVAL 30 DAY GROUP BY
        toDate(event_timestamp) as event_date,
        toStartOfHour(event_timestamp) as event_hour,
        event_type,
        country,
        device_type
    SET
        event_timestamp = min(event_timestamp),
        duration_seconds = sum(duration_seconds),
        revenue = sum(revenue),
        -- Keep first values for other columns
        user_id = any(user_id),
        session_id = any(session_id),
        page_url = any(page_url),
        browser = any(browser),
    -- Delete aggregated data after 90 days total
    event_date + INTERVAL 90 DAY DELETE;

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

-- TTL for daily user activity MV
-- Keep aggregated daily data for 1 year
ALTER TABLE daily_user_activity MODIFY TTL
    event_date + INTERVAL 1 YEAR DELETE;

-- TTL for hourly events MV
-- Keep hourly aggregations for 90 days (detailed), then keep daily for 1 year
ALTER TABLE mv_hourly_events MODIFY TTL
    event_date + INTERVAL 90 DAY DELETE;

-- TTL for product revenue MV
-- Keep product revenue data for 2 years
ALTER TABLE mv_product_revenue MODIFY TTL
    order_date + INTERVAL 2 YEAR DELETE;

-- TTL for user funnel MV
-- Keep conversion funnel data for 1 year
ALTER TABLE mv_user_funnel MODIFY TTL
    event_date + INTERVAL 1 YEAR DELETE;

-- TTL for country stats MV
-- Keep geographic data for 1 year
ALTER TABLE mv_country_stats MODIFY TTL
    event_date + INTERVAL 1 YEAR DELETE;

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

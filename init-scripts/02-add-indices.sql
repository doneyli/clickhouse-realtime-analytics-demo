-- ============================================================================
-- DATA SKIPPING INDICES FOR QUERY OPTIMIZATION
-- ============================================================================
-- These indices help ClickHouse skip irrelevant data granules during queries
-- Significantly improves query performance for filtered queries
-- ============================================================================

USE demo_db;

-- Add bloom filter index for session_id lookups
-- Bloom filters are perfect for equality checks on high-cardinality columns
-- Use case: Finding all events for a specific session
ALTER TABLE events ADD INDEX IF NOT EXISTS idx_session_id session_id
TYPE bloom_filter GRANULARITY 4;

-- Add minmax index for revenue filtering
-- MinMax indices store min/max values per granule
-- Use case: Queries like "WHERE revenue > 100"
ALTER TABLE events ADD INDEX IF NOT EXISTS idx_revenue revenue
TYPE minmax GRANULARITY 4;

-- Add set index for country filtering
-- Set indices store unique values per granule (up to max_size)
-- Use case: Queries like "WHERE country IN ('US', 'UK')"
ALTER TABLE events ADD INDEX IF NOT EXISTS idx_country country
TYPE set(100) GRANULARITY 4;

-- Add set index for event_type filtering
-- Critical for queries filtering by event type
ALTER TABLE events ADD INDEX IF NOT EXISTS idx_event_type event_type
TYPE set(50) GRANULARITY 4;

-- Add set index for device_type filtering
-- Useful for device-specific analytics
ALTER TABLE events ADD INDEX IF NOT EXISTS idx_device_type device_type
TYPE set(20) GRANULARITY 4;

-- Add minmax index for duration filtering on events
-- Use case: Finding long or short sessions
ALTER TABLE events ADD INDEX IF NOT EXISTS idx_duration duration_seconds
TYPE minmax GRANULARITY 4;

-- Orders table indices
-- Add set index for order status filtering
-- Most queries filter by status='completed'
ALTER TABLE orders ADD INDEX IF NOT EXISTS idx_status status
TYPE set(10) GRANULARITY 4;

-- Add set index for payment method analytics
ALTER TABLE orders ADD INDEX IF NOT EXISTS idx_payment_method payment_method
TYPE set(20) GRANULARITY 4;

-- Add minmax index for order amount filtering
-- Use case: High-value order analysis
ALTER TABLE orders ADD INDEX IF NOT EXISTS idx_amount total_amount
TYPE minmax GRANULARITY 4;

-- Products table indices
-- Add set index for category filtering
ALTER TABLE products ADD INDEX IF NOT EXISTS idx_category category
TYPE set(50) GRANULARITY 4;

-- Add minmax index for price range queries
ALTER TABLE products ADD INDEX IF NOT EXISTS idx_price price
TYPE minmax GRANULARITY 4;

-- Users table indices
-- Add set index for country in users table
ALTER TABLE users ADD INDEX IF NOT EXISTS idx_user_country country
TYPE set(100) GRANULARITY 4;

-- Add minmax index for age-based segmentation
ALTER TABLE users ADD INDEX IF NOT EXISTS idx_age age
TYPE minmax GRANULARITY 4;

-- Add minmax index for spending analysis
ALTER TABLE users ADD INDEX IF NOT EXISTS idx_spent total_spent
TYPE minmax GRANULARITY 4;

-- ============================================================================
-- MATERIALIZE INDICES
-- ============================================================================
-- Note: Indices are automatically applied to new data
-- To apply to existing data, use MATERIALIZE INDEX
-- This is optional but recommended for existing datasets
-- Uncomment the following lines if you have existing data:
-- ============================================================================

-- ALTER TABLE events MATERIALIZE INDEX idx_session_id;
-- ALTER TABLE events MATERIALIZE INDEX idx_revenue;
-- ALTER TABLE events MATERIALIZE INDEX idx_country;
-- ALTER TABLE events MATERIALIZE INDEX idx_event_type;
-- ALTER TABLE events MATERIALIZE INDEX idx_device_type;
-- ALTER TABLE events MATERIALIZE INDEX idx_duration;
-- ALTER TABLE orders MATERIALIZE INDEX idx_status;
-- ALTER TABLE orders MATERIALIZE INDEX idx_payment_method;
-- ALTER TABLE orders MATERIALIZE INDEX idx_amount;
-- ALTER TABLE products MATERIALIZE INDEX idx_category;
-- ALTER TABLE products MATERIALIZE INDEX idx_price;
-- ALTER TABLE users MATERIALIZE INDEX idx_user_country;
-- ALTER TABLE users MATERIALIZE INDEX idx_age;
-- ALTER TABLE users MATERIALIZE INDEX idx_spent;

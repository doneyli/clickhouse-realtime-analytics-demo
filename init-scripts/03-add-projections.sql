-- ============================================================================
-- PROJECTIONS FOR ALTERNATE SORT ORDERS
-- ============================================================================
-- Projections allow storing the same data with different sort orders
-- ClickHouse automatically selects the best projection for each query
-- More efficient than secondary indices - provides actual sorted data
-- ============================================================================

USE demo_db;

-- ============================================================================
-- EVENTS TABLE PROJECTIONS
-- ============================================================================

-- Projection optimized for country-based analytics
-- Use case: Geographic reporting, country-level metrics
-- Queries like: SELECT country, count() FROM events WHERE country = 'US'
ALTER TABLE events ADD PROJECTION IF NOT EXISTS proj_by_country
(
    SELECT *
    ORDER BY (country, event_date, event_type)
);

-- Projection optimized for user-centric queries
-- Use case: User behavior analysis, user timelines
-- Queries like: SELECT * FROM events WHERE user_id = 12345 ORDER BY event_timestamp
ALTER TABLE events ADD PROJECTION IF NOT EXISTS proj_by_user
(
    SELECT *
    ORDER BY (user_id, event_timestamp)
);

-- Projection optimized for session analysis
-- Use case: Session reconstruction, session-based analytics
-- Queries like: SELECT * FROM events WHERE session_id = 'xxx' ORDER BY event_timestamp
ALTER TABLE events ADD PROJECTION IF NOT EXISTS proj_by_session
(
    SELECT *
    ORDER BY (session_id, event_timestamp)
);

-- Projection with pre-aggregated daily stats
-- Use case: Dashboard queries for daily metrics
-- Demonstrates projection with aggregation
ALTER TABLE events ADD PROJECTION IF NOT EXISTS proj_daily_stats
(
    SELECT
        event_date,
        event_type,
        country,
        count() as event_count,
        uniq(user_id) as unique_users,
        sum(revenue) as total_revenue
    GROUP BY event_date, event_type, country
);

-- ============================================================================
-- ORDERS TABLE PROJECTIONS
-- ============================================================================

-- Projection optimized for product analysis
-- Use case: Product performance queries
-- Queries like: SELECT * FROM orders WHERE product_id = 123
ALTER TABLE orders ADD PROJECTION IF NOT EXISTS proj_by_product
(
    SELECT *
    ORDER BY (product_id, order_timestamp)
);

-- Projection optimized for user purchase history
-- Use case: Customer order history
-- Queries like: SELECT * FROM orders WHERE user_id = 456 ORDER BY order_timestamp DESC
ALTER TABLE orders ADD PROJECTION IF NOT EXISTS proj_by_user_orders
(
    SELECT *
    ORDER BY (user_id, order_timestamp)
);

-- ============================================================================
-- USERS TABLE PROJECTIONS
-- ============================================================================

-- Projection optimized for spending-based queries
-- Use case: High-value customer identification
-- Queries like: SELECT * FROM users WHERE total_spent > 1000 ORDER BY total_spent DESC
ALTER TABLE users ADD PROJECTION IF NOT EXISTS proj_by_spending
(
    SELECT *
    ORDER BY (is_premium, total_spent, user_id)
);

-- Projection optimized for registration cohort analysis
-- Use case: Cohort analysis by registration date
-- Queries like: SELECT * FROM users WHERE registration_date BETWEEN ... ORDER BY registration_date
ALTER TABLE users ADD PROJECTION IF NOT EXISTS proj_by_registration
(
    SELECT *
    ORDER BY (registration_date, country, user_id)
);

-- ============================================================================
-- MATERIALIZE PROJECTIONS
-- ============================================================================
-- Projections need to be materialized to apply to existing data
-- For new installations, this happens automatically
-- For existing data, uncomment these lines:
-- ============================================================================

-- Events projections (this may take a while on large datasets)
-- ALTER TABLE events MATERIALIZE PROJECTION proj_by_country;
-- ALTER TABLE events MATERIALIZE PROJECTION proj_by_user;
-- ALTER TABLE events MATERIALIZE PROJECTION proj_by_session;
-- ALTER TABLE events MATERIALIZE PROJECTION proj_daily_stats;

-- Orders projections
-- ALTER TABLE orders MATERIALIZE PROJECTION proj_by_product;
-- ALTER TABLE orders MATERIALIZE PROJECTION proj_by_user_orders;

-- Users projections
-- ALTER TABLE users MATERIALIZE PROJECTION proj_by_spending;
-- ALTER TABLE users MATERIALIZE PROJECTION proj_by_registration;

-- ============================================================================
-- HOW PROJECTIONS WORK
-- ============================================================================
-- 1. ClickHouse stores data in multiple sort orders within the same table
-- 2. Query optimizer automatically selects the best projection
-- 3. No manual query changes needed - completely transparent
-- 4. Storage cost: ~1.5-2x (compressed), but queries are 10-100x faster
-- 5. Projections update automatically on INSERT - no maintenance needed
--
-- Check which projection is used:
-- EXPLAIN SELECT ... FROM events WHERE country = 'US'
-- Look for "Projection Name: proj_by_country" in the output
-- ============================================================================

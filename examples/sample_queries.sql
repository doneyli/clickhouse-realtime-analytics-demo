-- ============================================================================
-- CLICKHOUSE REAL-TIME ANALYTICS - COMPREHENSIVE QUERY EXAMPLES
-- ============================================================================
-- This file showcases ClickHouse's advanced features for real-time analytics
-- Run these queries to explore the optimizations implemented in this demo
-- ============================================================================

USE demo_db;

-- ============================================================================
-- SECTION 1: BASIC ANALYTICS WITH OPTIMIZED TABLES
-- ============================================================================

-- Example 1.1: User distribution by country
-- Uses LowCardinality optimization and optimized ORDER BY
SELECT
    country,
    COUNT(*) as user_count,
    AVG(age) as avg_age,
    SUM(is_premium) as premium_users,
    SUM(total_spent) as total_spent
FROM users
GROUP BY country
ORDER BY user_count DESC
LIMIT 10;

-- Example 1.2: Event distribution with data skipping indices
-- The idx_event_type set index helps filter events efficiently
SELECT
    event_type,
    COUNT(*) as event_count,
    uniq(user_id) as unique_users,
    SUM(revenue) as total_revenue,
    AVG(duration_seconds) as avg_duration
FROM events
WHERE event_type IN ('purchase', 'add_to_cart', 'page_view')
  AND event_date >= today() - INTERVAL 7 DAY
GROUP BY event_type
ORDER BY event_count DESC;

-- ============================================================================
-- SECTION 2: MATERIALIZED VIEWS FOR FAST AGGREGATIONS
-- ============================================================================

-- Example 2.1: Query hourly events MV instead of raw events
-- 10-100x faster than scanning raw events table
SELECT
    event_date,
    event_hour,
    event_type,
    SUM(event_count) as total_events,
    SUM(unique_users) as unique_users,
    SUM(total_revenue) as revenue
FROM mv_hourly_events
WHERE event_date >= today() - INTERVAL 7 DAY
GROUP BY event_date, event_hour, event_type
ORDER BY event_date DESC, event_hour DESC
LIMIT 100;

-- Example 2.2: Product revenue analysis using MV (no JOIN needed!)
-- Eliminates expensive JOIN between orders and products
SELECT
    p.product_name,
    p.category,
    SUM(mv.total_revenue) as revenue,
    SUM(mv.order_count) as orders,
    AVG(mv.avg_order_value) as avg_order_value
FROM mv_product_revenue mv
JOIN products p ON mv.product_id = p.product_id
WHERE mv.status = 'completed'
  AND mv.order_date >= today() - INTERVAL 30 DAY
GROUP BY p.product_id, p.product_name, p.category
ORDER BY revenue DESC
LIMIT 20;

-- Example 2.3: Conversion funnel using AggregatingMergeTree MV
-- Demonstrates State functions for complex aggregations
SELECT
    countMerge(total_events) as total_events,
    sumMerge(page_views) as page_views,
    sumMerge(cart_adds) as cart_adds,
    sumMerge(purchases) as purchases,
    sumMerge(total_revenue) as revenue,
    round(sumMerge(purchases) * 100.0 / sumMerge(page_views), 2) as conversion_rate,
    round(sumMerge(cart_adds) * 100.0 / sumMerge(page_views), 2) as cart_rate
FROM mv_user_funnel
WHERE event_date >= today() - INTERVAL 30 DAY;

-- Example 2.4: Geographic analytics using country stats MV
SELECT
    country,
    SUM(event_count) as total_events,
    SUM(unique_users) as unique_users,
    SUM(total_revenue) as revenue,
    round(revenue / unique_users, 2) as revenue_per_user
FROM mv_country_stats
WHERE event_date >= today() - INTERVAL 30 DAY
GROUP BY country
ORDER BY revenue DESC
LIMIT 15;

-- ============================================================================
-- SECTION 3: PROJECTIONS FOR ALTERNATE SORT ORDERS
-- ============================================================================

-- Example 3.1: User timeline query (uses proj_by_user projection)
-- Query optimizer automatically selects the best projection
SELECT
    event_id,
    event_type,
    event_timestamp,
    page_url,
    revenue
FROM events
WHERE user_id = 1234
ORDER BY event_timestamp DESC
LIMIT 50;

-- Example 3.2: Country-based analysis (uses proj_by_country projection)
SELECT
    country,
    event_type,
    COUNT(*) as events,
    SUM(revenue) as revenue
FROM events
WHERE country = 'US'
  AND event_date >= today() - INTERVAL 7 DAY
GROUP BY country, event_type
ORDER BY events DESC;

-- Example 3.3: Session reconstruction (uses proj_by_session projection)
SELECT
    session_id,
    event_timestamp,
    event_type,
    page_url,
    duration_seconds
FROM events
WHERE session_id = 'some-session-id'
ORDER BY event_timestamp;

-- Example 3.4: High-value customer query (uses proj_by_spending projection)
SELECT
    user_id,
    username,
    country,
    total_spent,
    registration_date
FROM users
WHERE is_premium = 1
  AND total_spent > 1000
ORDER BY total_spent DESC
LIMIT 100;

-- To verify which projection is used:
-- EXPLAIN SELECT ... FROM events WHERE user_id = 1234;
-- Look for "Projection Name: proj_by_user" in the output

-- ============================================================================
-- SECTION 4: DICTIONARIES FOR FAST DIMENSION ENRICHMENT
-- ============================================================================

-- Example 4.1: Enrich events with user data using dictionary (fast!)
-- Much faster than JOIN for dimension lookups
SELECT
    e.event_id,
    e.user_id,
    dictGet('dict_users', 'username', e.user_id) as username,
    dictGet('dict_users', 'country', e.user_id) as country,
    dictGet('dict_users', 'is_premium', e.user_id) as is_premium,
    e.event_type,
    e.revenue
FROM events e
WHERE e.event_date = today()
LIMIT 100;

-- Example 4.2: Enrich orders with product details using dictionary
SELECT
    o.order_id,
    o.user_id,
    dictGet('dict_products', 'product_name', o.product_id) as product_name,
    dictGet('dict_products', 'category', o.product_id) as category,
    dictGet('dict_products', 'price', o.product_id) as product_price,
    o.quantity,
    o.total_amount
FROM orders o
WHERE o.order_date = today()
  AND o.status = 'completed'
LIMIT 100;

-- Example 4.3: Multi-level enrichment with geographic metadata
SELECT
    e.event_id,
    dictGet('dict_users', 'country', e.user_id) as country_code,
    dictGet('dict_country_metadata', 'country_name', country_code) as country_name,
    dictGet('dict_country_metadata', 'region', country_code) as region,
    dictGet('dict_country_metadata', 'continent', country_code) as continent,
    dictGet('dict_country_metadata', 'currency', country_code) as currency,
    e.event_type,
    e.revenue
FROM events e
WHERE e.event_date >= today() - INTERVAL 7 DAY
LIMIT 100;

-- Example 4.4: Product category enrichment with commission calculation
SELECT
    p.product_id,
    p.product_name,
    p.category,
    dictGet('dict_category_metadata', 'category_display', p.category) as category_display,
    dictGet('dict_category_metadata', 'parent_category', p.category) as parent_category,
    dictGet('dict_category_metadata', 'commission_rate', p.category) as commission_rate,
    SUM(o.total_amount) as revenue,
    round(SUM(o.total_amount) * commission_rate / 100, 2) as estimated_commission
FROM orders o
JOIN products p ON o.product_id = p.product_id
WHERE o.status = 'completed'
  AND o.order_date >= today() - INTERVAL 30 DAY
GROUP BY p.product_id, p.product_name, p.category
ORDER BY revenue DESC
LIMIT 20;

-- ============================================================================
-- SECTION 5: REFRESHABLE MATERIALIZED VIEWS
-- ============================================================================

-- Example 5.1: Query top products ranking
-- Rankings can't be incremental, so we use Refreshable MV
SELECT
    rank,
    product_name,
    category,
    total_revenue,
    total_orders,
    round(avg_order_value, 2) as avg_order_value
FROM mv_top_products_ranking
WHERE rank_date = today()
ORDER BY rank
LIMIT 20;

-- Example 5.2: Customer Lifetime Value analysis
-- Complex calculation with RFM scores and percentiles
SELECT
    user_id,
    username,
    country,
    ltv_segment,
    lifetime_value,
    total_orders,
    recency_days,
    round(recency_percentile * 100, 1) as recency_score,
    round(frequency_percentile * 100, 1) as frequency_score,
    round(monetary_percentile * 100, 1) as monetary_score
FROM mv_customer_ltv
WHERE ltv_segment IN ('High Value', 'Medium Value')
ORDER BY lifetime_value DESC
LIMIT 50;

-- Example 5.3: Cohort retention analysis
-- Shows user retention by registration cohort
SELECT
    toStartOfMonth(cohort_month) as cohort,
    cohort_size,
    retention_pct_month_1 as month_1_retention,
    retention_pct_month_2 as month_2_retention,
    retention_pct_month_3 as month_3_retention,
    retention_pct_month_6 as month_6_retention
FROM mv_cohort_retention
ORDER BY cohort DESC
LIMIT 12;

-- Example 5.4: Product affinity / market basket analysis
-- Find products frequently purchased together
SELECT
    product_1_name,
    product_1_category,
    product_2_name,
    product_2_category,
    co_purchase_count,
    round(affinity_score * 100, 2) as affinity_pct
FROM mv_product_affinity
WHERE product_1_name LIKE '%Laptop%'  -- Replace with actual product
ORDER BY co_purchase_count DESC
LIMIT 10;

-- Example 5.5: Daily KPI snapshot
-- Single query for all key business metrics
SELECT
    metric_date,
    last_updated,
    total_users,
    premium_users,
    new_users_today,
    active_users_today,
    active_users_7d,
    active_users_30d,
    round(revenue_today, 2) as revenue_today,
    round(revenue_7d, 2) as revenue_7d,
    round(revenue_30d, 2) as revenue_30d,
    orders_today,
    round(avg_order_value_today, 2) as avg_order_value,
    conversion_rate_today
FROM mv_daily_kpi_summary
WHERE metric_date = today();

-- ============================================================================
-- SECTION 6: WINDOW FUNCTIONS
-- ============================================================================

-- Example 6.1: Top products per category using window functions
SELECT
    category,
    product_name,
    revenue,
    rank
FROM (
    SELECT
        p.category,
        p.product_name,
        SUM(o.total_amount) as revenue,
        row_number() OVER (PARTITION BY p.category ORDER BY SUM(o.total_amount) DESC) as rank
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    WHERE o.status = 'completed'
      AND o.order_date >= today() - INTERVAL 30 DAY
    GROUP BY p.category, p.product_id, p.product_name
)
WHERE rank <= 5
ORDER BY category, rank;

-- Example 6.2: User activity trends with running totals
SELECT
    event_date,
    event_count,
    sum(event_count) OVER (ORDER BY event_date) as cumulative_events,
    avg(event_count) OVER (ORDER BY event_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as moving_avg_7d
FROM (
    SELECT
        event_date,
        COUNT(*) as event_count
    FROM events
    WHERE event_date >= today() - INTERVAL 30 DAY
    GROUP BY event_date
)
ORDER BY event_date;

-- Example 6.3: Customer ranking by spending with percentiles
SELECT
    user_id,
    username,
    total_spent,
    row_number() OVER (ORDER BY total_spent DESC) as rank,
    percent_rank() OVER (ORDER BY total_spent DESC) as percentile,
    ntile(10) OVER (ORDER BY total_spent DESC) as decile
FROM users
WHERE total_spent > 0
ORDER BY total_spent DESC
LIMIT 100;

-- ============================================================================
-- SECTION 7: ADVANCED QUERY PATTERNS
-- ============================================================================

-- Example 7.1: Time-series analysis with gaps filled
-- Fill missing dates with zeros
SELECT
    d.date,
    coalesce(e.event_count, 0) as events,
    coalesce(e.unique_users, 0) as users
FROM (
    SELECT toDate(now() - INTERVAL number DAY) as date
    FROM numbers(30)
) d
LEFT JOIN (
    SELECT
        event_date as date,
        COUNT(*) as event_count,
        uniq(user_id) as unique_users
    FROM events
    WHERE event_date >= today() - INTERVAL 30 DAY
    GROUP BY event_date
) e ON d.date = e.date
ORDER BY d.date;

-- Example 7.2: Funnel analysis with step-by-step conversion
WITH funnel_steps AS (
    SELECT
        user_id,
        max(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) as step_1_view,
        max(CASE WHEN event_type = 'add_to_cart' THEN 1 ELSE 0 END) as step_2_cart,
        max(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) as step_3_purchase
    FROM events
    WHERE event_date >= today() - INTERVAL 30 DAY
    GROUP BY user_id
)
SELECT
    'Step 1: Page View' as step,
    SUM(step_1_view) as users,
    100.0 as conversion_rate
FROM funnel_steps
UNION ALL
SELECT
    'Step 2: Add to Cart',
    SUM(step_2_cart),
    SUM(step_2_cart) * 100.0 / SUM(step_1_view)
FROM funnel_steps
UNION ALL
SELECT
    'Step 3: Purchase',
    SUM(step_3_purchase),
    SUM(step_3_purchase) * 100.0 / SUM(step_2_cart)
FROM funnel_steps;

-- Example 7.3: Sessionization - group events into sessions
-- Events within 30 minutes belong to same session
SELECT
    user_id,
    session_start,
    COUNT(*) as events_in_session,
    SUM(duration_seconds) as total_duration,
    SUM(revenue) as session_revenue,
    arrayStringConcat(groupArray(event_type), ' → ') as event_sequence
FROM (
    SELECT
        user_id,
        event_id,
        event_type,
        event_timestamp,
        duration_seconds,
        revenue,
        toStartOfInterval(event_timestamp, INTERVAL 30 MINUTE) as session_start
    FROM events
    WHERE user_id = 1234  -- Replace with actual user_id
      AND event_date >= today() - INTERVAL 7 DAY
    ORDER BY event_timestamp
)
GROUP BY user_id, session_start
ORDER BY session_start DESC;

-- Example 7.4: PREWHERE optimization for efficient filtering
-- PREWHERE evaluates filter before reading all columns
SELECT
    event_id,
    user_id,
    event_type,
    event_timestamp,
    page_url,
    revenue
FROM events
PREWHERE event_type = 'purchase'  -- Evaluated first, on primary key columns
WHERE revenue > 100  -- Evaluated after PREWHERE
  AND event_date >= today() - INTERVAL 7 DAY
ORDER BY revenue DESC
LIMIT 100;

-- ============================================================================
-- SECTION 8: QUERY PERFORMANCE ANALYSIS
-- ============================================================================

-- Example 8.1: Check which projection is used
EXPLAIN
SELECT * FROM events WHERE user_id = 1234 ORDER BY event_timestamp;
-- Look for "Projection Name: proj_by_user"

-- Example 8.2: Analyze query execution plan
EXPLAIN PIPELINE
SELECT
    country,
    COUNT(*) as cnt
FROM events
WHERE event_date = today()
  AND country = 'US'
GROUP BY country;

-- Example 8.3: Check index usage
EXPLAIN indexes = 1
SELECT * FROM events
WHERE country IN ('US', 'UK')
  AND event_date >= today() - INTERVAL 7 DAY;
-- Shows which indices (idx_country) are used

-- Example 8.4: Query execution statistics
SELECT
    query,
    query_duration_ms,
    read_rows,
    read_bytes,
    result_rows,
    memory_usage
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query_duration_ms > 100
  AND event_time >= now() - INTERVAL 1 HOUR
ORDER BY query_duration_ms DESC
LIMIT 10;

-- ============================================================================
-- SECTION 9: CHECKING OPTIMIZATIONS
-- ============================================================================

-- Check compression effectiveness
SELECT
    table,
    formatReadableSize(sum(bytes_on_disk)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size,
    round(sum(data_uncompressed_bytes) / sum(bytes_on_disk), 2) as compression_ratio
FROM system.parts
WHERE active AND database = 'demo_db'
GROUP BY table
ORDER BY table;

-- Check dictionary status
SELECT
    name,
    status,
    element_count,
    bytes_allocated,
    loading_duration,
    last_successful_update_time
FROM system.dictionaries
WHERE database = 'demo_db';

-- Check table sizes and row counts
SELECT
    table,
    formatReadableSize(sum(bytes_on_disk)) as size,
    sum(rows) as rows,
    max(modification_time) as last_modified
FROM system.parts
WHERE active AND database = 'demo_db'
GROUP BY table
ORDER BY sum(bytes_on_disk) DESC;

-- Check materialized views and their dependencies
SELECT
    name,
    engine,
    total_rows,
    total_bytes
FROM system.tables
WHERE database = 'demo_db'
  AND (engine LIKE '%MergeTree%' OR engine LIKE '%View%')
ORDER BY total_bytes DESC;

-- ============================================================================
-- END OF EXAMPLES
-- ============================================================================
-- These queries demonstrate ClickHouse's capabilities for real-time analytics:
-- - LowCardinality and compression for storage efficiency
-- - Materialized views for pre-aggregated fast queries
-- - Projections for multiple sort orders without duplication
-- - Dictionaries for O(1) dimension lookups
-- - Data skipping indices for filtered query performance
-- - Window functions for complex analytics
-- - TTL for automatic data lifecycle management
--
-- For more information, see the SQL files in init-scripts/
-- ============================================================================

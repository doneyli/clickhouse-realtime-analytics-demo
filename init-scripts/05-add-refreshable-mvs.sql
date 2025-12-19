-- ============================================================================
-- REFRESHABLE MATERIALIZED VIEWS FOR COMPLEX ANALYTICS
-- ============================================================================
-- Refreshable MVs are perfect for complex queries that can't be incrementally
-- updated (e.g., rankings, percentiles, complex JOINs with window functions)
-- They refresh on a schedule instead of on every INSERT
-- ============================================================================

USE demo_db;

-- ============================================================================
-- TOP PRODUCTS RANKING - REFRESHABLE MV
-- ============================================================================
-- Rankings can't be incrementally updated, so use Refreshable MV
-- Recalculates top products every hour

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_top_products_ranking
REFRESH EVERY 1 HOUR
ENGINE = MergeTree
ORDER BY (rank_date, rank)
AS SELECT
    today() as rank_date,
    row_number() OVER (ORDER BY total_revenue DESC) as rank,
    product_id,
    product_name,
    category,
    total_revenue,
    total_orders,
    avg_order_value
FROM (
    SELECT
        p.product_id,
        p.product_name,
        p.category,
        sum(mv.total_revenue) as total_revenue,
        sum(mv.order_count) as total_orders,
        avg(mv.avg_order_value) as avg_order_value
    FROM mv_product_revenue mv
    JOIN products p ON mv.product_id = p.product_id
    WHERE mv.status = 'completed'
    AND mv.order_date >= today() - INTERVAL 30 DAY
    GROUP BY p.product_id, p.product_name, p.category
)
ORDER BY rank
LIMIT 100;

-- ============================================================================
-- CUSTOMER LIFETIME VALUE (CLV) - REFRESHABLE MV
-- ============================================================================
-- Complex calculation requiring multiple aggregations and window functions
-- Refreshes every 6 hours

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_customer_ltv
REFRESH EVERY 6 HOUR
ENGINE = MergeTree
ORDER BY (ltv_segment, user_id)
AS SELECT
    u.user_id,
    u.username,
    u.country,
    u.is_premium,
    u.registration_date,
    o.total_orders,
    o.lifetime_value,
    o.first_order_date,
    o.last_order_date,
    o.avg_order_value,
    dateDiff('day', o.first_order_date, o.last_order_date) as customer_age_days,
    dateDiff('day', u.registration_date, today()) as days_since_registration,
    CASE
        WHEN o.lifetime_value >= 1000 THEN 'High Value'
        WHEN o.lifetime_value >= 500 THEN 'Medium Value'
        WHEN o.lifetime_value >= 100 THEN 'Low Value'
        ELSE 'New Customer'
    END as ltv_segment,
    -- RFM Score components
    dateDiff('day', o.last_order_date, today()) as recency_days,
    o.total_orders as frequency,
    o.lifetime_value as monetary,
    -- Percentile rankings
    percent_rank() OVER (ORDER BY dateDiff('day', o.last_order_date, today()) ASC) as recency_percentile,
    percent_rank() OVER (ORDER BY o.total_orders DESC) as frequency_percentile,
    percent_rank() OVER (ORDER BY o.lifetime_value DESC) as monetary_percentile
FROM users u
LEFT JOIN (
    SELECT
        user_id,
        count() as total_orders,
        sum(total_amount) as lifetime_value,
        min(order_date) as first_order_date,
        max(order_date) as last_order_date,
        avg(total_amount) as avg_order_value
    FROM orders
    WHERE status = 'completed'
    GROUP BY user_id
) o ON u.user_id = o.user_id
WHERE o.user_id IS NOT NULL;

-- ============================================================================
-- COHORT RETENTION ANALYSIS - REFRESHABLE MV
-- ============================================================================
-- Cohort analysis with retention metrics
-- Refreshes daily at 2 AM

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_cohort_retention
REFRESH EVERY 1 DAY
ENGINE = MergeTree
ORDER BY (cohort_month, cohort_week)
AS
WITH user_cohorts AS (
    SELECT
        user_id,
        toStartOfMonth(registration_date) as cohort_month,
        toMonday(registration_date) as cohort_week,
        registration_date
    FROM users
),
user_activity AS (
    SELECT
        e.user_id,
        toStartOfMonth(e.event_date) as activity_month,
        toMonday(e.event_date) as activity_week
    FROM events e
    GROUP BY e.user_id, activity_month, activity_week
)
SELECT
    uc.cohort_month,
    uc.cohort_week,
    count(DISTINCT uc.user_id) as cohort_size,
    -- Month retention
    count(DISTINCT CASE WHEN dateDiff('month', uc.cohort_month, ua.activity_month) = 0 THEN ua.user_id END) as retained_month_0,
    count(DISTINCT CASE WHEN dateDiff('month', uc.cohort_month, ua.activity_month) = 1 THEN ua.user_id END) as retained_month_1,
    count(DISTINCT CASE WHEN dateDiff('month', uc.cohort_month, ua.activity_month) = 2 THEN ua.user_id END) as retained_month_2,
    count(DISTINCT CASE WHEN dateDiff('month', uc.cohort_month, ua.activity_month) = 3 THEN ua.user_id END) as retained_month_3,
    count(DISTINCT CASE WHEN dateDiff('month', uc.cohort_month, ua.activity_month) = 6 THEN ua.user_id END) as retained_month_6,
    -- Retention percentages
    round(retained_month_1 * 100.0 / cohort_size, 2) as retention_pct_month_1,
    round(retained_month_2 * 100.0 / cohort_size, 2) as retention_pct_month_2,
    round(retained_month_3 * 100.0 / cohort_size, 2) as retention_pct_month_3,
    round(retained_month_6 * 100.0 / cohort_size, 2) as retention_pct_month_6
FROM user_cohorts uc
LEFT JOIN user_activity ua ON uc.user_id = ua.user_id
GROUP BY uc.cohort_month, uc.cohort_week
HAVING cohort_size > 0
ORDER BY uc.cohort_month DESC;

-- ============================================================================
-- PRODUCT AFFINITY / MARKET BASKET ANALYSIS - REFRESHABLE MV
-- ============================================================================
-- Find products frequently purchased together
-- Refreshes every 12 hours

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_product_affinity
REFRESH EVERY 12 HOUR
ENGINE = MergeTree
ORDER BY (product_1_id, product_2_id)
AS
WITH user_purchases AS (
    SELECT DISTINCT
        user_id,
        product_id
    FROM orders
    WHERE status = 'completed'
    AND order_date >= today() - INTERVAL 90 DAY
)
SELECT
    p1.product_id as product_1_id,
    p1_info.product_name as product_1_name,
    p1_info.category as product_1_category,
    p2.product_id as product_2_id,
    p2_info.product_name as product_2_name,
    p2_info.category as product_2_category,
    count(*) as co_purchase_count,
    count(*) * 1.0 / (
        SELECT count(DISTINCT user_id)
        FROM user_purchases
        WHERE product_id = p1.product_id
    ) as affinity_score
FROM user_purchases p1
JOIN user_purchases p2 ON p1.user_id = p2.user_id AND p1.product_id < p2.product_id
JOIN products p1_info ON p1.product_id = p1_info.product_id
JOIN products p2_info ON p2.product_id = p2_info.product_id
GROUP BY
    p1.product_id, p1_info.product_name, p1_info.category,
    p2.product_id, p2_info.product_name, p2_info.category
HAVING co_purchase_count >= 5
ORDER BY co_purchase_count DESC
LIMIT 1000;

-- ============================================================================
-- DAILY BUSINESS METRICS SUMMARY - REFRESHABLE MV
-- ============================================================================
-- Comprehensive daily KPI dashboard
-- Refreshes every hour

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_kpi_summary
REFRESH EVERY 1 HOUR
ENGINE = ReplacingMergeTree()
ORDER BY (metric_date)
AS SELECT
    today() as metric_date,
    now() as last_updated,
    -- User metrics
    (SELECT count() FROM users) as total_users,
    (SELECT count() FROM users WHERE is_premium = 1) as premium_users,
    (SELECT count() FROM users WHERE registration_date = today()) as new_users_today,
    -- Event metrics
    (SELECT count() FROM events WHERE event_date = today()) as events_today,
    (SELECT uniq(user_id) FROM events WHERE event_date = today()) as active_users_today,
    (SELECT uniq(user_id) FROM events WHERE event_date >= today() - INTERVAL 7 DAY) as active_users_7d,
    (SELECT uniq(user_id) FROM events WHERE event_date >= today() - INTERVAL 30 DAY) as active_users_30d,
    -- Revenue metrics
    (SELECT sum(total_amount) FROM orders WHERE order_date = today() AND status = 'completed') as revenue_today,
    (SELECT sum(total_amount) FROM orders WHERE order_date >= today() - INTERVAL 7 DAY AND status = 'completed') as revenue_7d,
    (SELECT sum(total_amount) FROM orders WHERE order_date >= today() - INTERVAL 30 DAY AND status = 'completed') as revenue_30d,
    (SELECT count() FROM orders WHERE order_date = today() AND status = 'completed') as orders_today,
    (SELECT avg(total_amount) FROM orders WHERE order_date = today() AND status = 'completed') as avg_order_value_today,
    -- Conversion metrics
    (SELECT count() FROM events WHERE event_date = today() AND event_type = 'page_view') as page_views_today,
    (SELECT count() FROM events WHERE event_date = today() AND event_type = 'purchase') as purchases_today,
    round(purchases_today * 100.0 / nullIf(page_views_today, 0), 2) as conversion_rate_today;

-- ============================================================================
-- BENEFITS OF REFRESHABLE MVS
-- ============================================================================
-- 1. Complex queries: Window functions, rankings, percentiles
-- 2. Cross-table JOINs: Without performance impact
-- 3. Scheduled refresh: Control when computation happens
-- 4. Resource efficient: Compute during off-peak hours
-- 5. Always available: Queries read pre-computed results
--
-- Use regular MVs for: Incremental aggregations (sums, counts)
-- Use refreshable MVs for: Rankings, percentiles, complex JOINs
-- ============================================================================

-- ============================================================================
-- QUERY EXAMPLES
-- ============================================================================

-- Get top 10 products from ranking MV:
-- SELECT * FROM mv_top_products_ranking WHERE rank_date = today() LIMIT 10;

-- Find high-value customers for targeted marketing:
-- SELECT * FROM mv_customer_ltv WHERE ltv_segment = 'High Value' ORDER BY lifetime_value DESC;

-- Check cohort retention rates:
-- SELECT cohort_month, cohort_size, retention_pct_month_1, retention_pct_month_3
-- FROM mv_cohort_retention ORDER BY cohort_month DESC LIMIT 12;

-- Product recommendations (market basket):
-- SELECT product_2_name, co_purchase_count, affinity_score
-- FROM mv_product_affinity WHERE product_1_name = 'Some Product' ORDER BY affinity_score DESC LIMIT 10;

-- Today's business snapshot:
-- SELECT * FROM mv_daily_kpi_summary WHERE metric_date = today();

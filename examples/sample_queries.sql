-- ClickHouse Analytics Demo - Sample Queries
-- This file contains useful analytical queries for exploring the demo data

-- =============================================================================
-- USER ANALYTICS
-- =============================================================================

-- Top countries by user count
SELECT 
    country,
    COUNT(*) as user_count,
    AVG(age) as avg_age,
    SUM(is_premium) as premium_users
FROM users 
GROUP BY country 
ORDER BY user_count DESC 
LIMIT 10;

-- Premium vs Regular user comparison
SELECT 
    is_premium,
    COUNT(*) as users,
    AVG(age) as avg_age,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() as percentage
FROM users 
GROUP BY is_premium;

-- =============================================================================
-- EVENT ANALYTICS
-- =============================================================================

-- Daily event trends (last 30 days)
SELECT 
    toDate(event_timestamp) as date,
    event_type,
    COUNT(*) as event_count
FROM events 
WHERE event_timestamp >= now() - INTERVAL 30 DAY
GROUP BY date, event_type
ORDER BY date DESC, event_count DESC;

-- Most active users by events
SELECT 
    u.username,
    u.country,
    COUNT(e.event_id) as total_events,
    COUNT(DISTINCT toDate(e.event_timestamp)) as active_days
FROM users u
JOIN events e ON u.user_id = e.user_id
GROUP BY u.user_id, u.username, u.country
ORDER BY total_events DESC
LIMIT 20;

-- =============================================================================
-- REVENUE ANALYTICS
-- =============================================================================

-- Monthly revenue trends
SELECT 
    toYYYYMM(order_timestamp) as month,
    COUNT(*) as order_count,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_order_value
FROM orders 
GROUP BY month 
ORDER BY month DESC;

-- Top products by revenue
SELECT 
    p.product_name,
    p.category,
    COUNT(o.order_id) as orders,
    SUM(o.total_amount) as revenue
FROM products p
JOIN orders o ON p.product_id = o.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY revenue DESC
LIMIT 15;

-- Revenue by country
SELECT 
    u.country,
    COUNT(o.order_id) as orders,
    SUM(o.total_amount) as total_revenue,
    AVG(o.total_amount) as avg_order_value
FROM users u
JOIN orders o ON u.user_id = o.user_id
GROUP BY u.country
ORDER BY total_revenue DESC;

-- =============================================================================
-- CONVERSION ANALYTICS
-- =============================================================================

-- Conversion funnel: page_view → purchase
WITH user_events AS (
    SELECT 
        user_id,
        SUM(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) as page_views,
        SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) as purchases
    FROM events
    GROUP BY user_id
)
SELECT 
    COUNT(*) as total_users,
    SUM(CASE WHEN page_views > 0 THEN 1 ELSE 0 END) as users_with_page_views,
    SUM(CASE WHEN purchases > 0 THEN 1 ELSE 0 END) as users_with_purchases,
    SUM(purchases) * 100.0 / SUM(page_views) as conversion_rate
FROM user_events;

-- =============================================================================
-- TIME-BASED ANALYTICS
-- =============================================================================

-- Hourly activity patterns
SELECT 
    toHour(event_timestamp) as hour,
    COUNT(*) as events,
    COUNT(DISTINCT user_id) as unique_users
FROM events
GROUP BY hour
ORDER BY hour;

-- Day of week analysis
SELECT 
    toDayOfWeek(event_timestamp) as day_of_week,
    CASE toDayOfWeek(event_timestamp)
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday' 
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
        WHEN 7 THEN 'Sunday'
    END as day_name,
    COUNT(*) as events,
    SUM(CASE WHEN e.event_type = 'purchase' THEN 1 ELSE 0 END) as purchases
FROM events e
GROUP BY day_of_week, day_name
ORDER BY day_of_week;

-- =============================================================================
-- ADVANCED ANALYTICS
-- =============================================================================

-- Customer lifetime value (CLV)
SELECT 
    u.user_id,
    u.username,
    u.country,
    u.is_premium,
    COUNT(o.order_id) as total_orders,
    SUM(o.total_amount) as lifetime_value,
    MIN(o.order_timestamp) as first_order,
    MAX(o.order_timestamp) as last_order,
    dateDiff('day', MIN(o.order_timestamp), MAX(o.order_timestamp)) as customer_lifespan_days
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
WHERE o.order_id IS NOT NULL
GROUP BY u.user_id, u.username, u.country, u.is_premium
HAVING lifetime_value > 0
ORDER BY lifetime_value DESC
LIMIT 50;

-- Cohort analysis - user retention by registration month
SELECT 
    toYYYYMM(registration_date) as cohort_month,
    COUNT(DISTINCT user_id) as cohort_size,
    COUNT(DISTINCT CASE WHEN dateDiff('month', registration_date, now()) >= 1 THEN user_id END) as retained_1_month,
    COUNT(DISTINCT CASE WHEN dateDiff('month', registration_date, now()) >= 3 THEN user_id END) as retained_3_months
FROM users
GROUP BY cohort_month
ORDER BY cohort_month DESC;

-- Product affinity analysis
SELECT 
    p1.product_name as product_1,
    p2.product_name as product_2,
    COUNT(*) as co_purchases
FROM orders o1
JOIN orders o2 ON o1.user_id = o2.user_id AND o1.order_id != o2.order_id
JOIN products p1 ON o1.product_id = p1.product_id
JOIN products p2 ON o2.product_id = p2.product_id
WHERE p1.product_id < p2.product_id  -- Avoid duplicates
GROUP BY p1.product_id, p1.product_name, p2.product_id, p2.product_name
HAVING co_purchases > 5
ORDER BY co_purchases DESC
LIMIT 20;

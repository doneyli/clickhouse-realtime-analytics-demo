-- ============================================================================
-- DICTIONARIES FOR FAST DIMENSION LOOKUPS
-- ============================================================================
-- Dictionaries provide O(1) lookup performance for dimension enrichment
-- Much faster than JOINs for dimension table lookups
-- Automatically cached in memory for instant access
-- ============================================================================

USE demo_db;

-- ============================================================================
-- USERS DICTIONARY
-- ============================================================================
-- Enable fast user attribute lookups without JOINs
-- Use case: Enrich events with user data (country, premium status, etc.)

CREATE DICTIONARY IF NOT EXISTS dict_users
(
    user_id UInt64,
    username String,
    email String,
    age UInt8,
    country String,
    registration_date Date,
    is_premium UInt8,
    total_spent Decimal(10,2)
)
PRIMARY KEY user_id
SOURCE(CLICKHOUSE(
    HOST 'localhost'
    PORT 9000
    USER 'demo_user'
    PASSWORD 'demo_password'
    DB 'demo_db'
    TABLE 'users'
))
LAYOUT(HASHED())  -- In-memory hash table for O(1) lookups
LIFETIME(MIN 300 MAX 600);  -- Reload every 5-10 minutes

-- ============================================================================
-- PRODUCTS DICTIONARY
-- ============================================================================
-- Fast product attribute lookups
-- Use case: Enrich orders/events with product details

CREATE DICTIONARY IF NOT EXISTS dict_products
(
    product_id UInt64,
    product_name String,
    category String,
    price Decimal(10,2),
    created_date Date,
    is_active UInt8
)
PRIMARY KEY product_id
SOURCE(CLICKHOUSE(
    HOST 'localhost'
    PORT 9000
    USER 'demo_user'
    PASSWORD 'demo_password'
    DB 'demo_db'
    TABLE 'products'
))
LAYOUT(HASHED())
LIFETIME(MIN 300 MAX 600);

-- ============================================================================
-- COUNTRY METADATA DICTIONARY (Static)
-- ============================================================================
-- Geographic enrichment data
-- For demo purposes, using inline data source

CREATE DICTIONARY IF NOT EXISTS dict_country_metadata
(
    country_code String,
    country_name String,
    region String,
    continent String,
    currency String,
    timezone_offset Int8
)
PRIMARY KEY country_code
SOURCE(CLICKHOUSE(
    QUERY 'SELECT * FROM (
        SELECT ''US'' AS country_code, ''United States'' AS country_name, ''North America'' AS region, ''Americas'' AS continent, ''USD'' AS currency, -5 AS timezone_offset
        UNION ALL SELECT ''UK'', ''United Kingdom'', ''Europe'', ''Europe'', ''GBP'', 0
        UNION ALL SELECT ''DE'', ''Germany'', ''Europe'', ''Europe'', ''EUR'', 1
        UNION ALL SELECT ''FR'', ''France'', ''Europe'', ''Europe'', ''EUR'', 1
        UNION ALL SELECT ''CA'', ''Canada'', ''North America'', ''Americas'', ''CAD'', -5
        UNION ALL SELECT ''AU'', ''Australia'', ''Oceania'', ''Oceania'', ''AUD'', 10
        UNION ALL SELECT ''JP'', ''Japan'', ''Asia'', ''Asia'', ''JPY'', 9
        UNION ALL SELECT ''BR'', ''Brazil'', ''South America'', ''Americas'', ''BRL'', -3
        UNION ALL SELECT ''IN'', ''India'', ''Asia'', ''Asia'', ''INR'', 5
        UNION ALL SELECT ''RU'', ''Russia'', ''Europe/Asia'', ''Europe'', ''RUB'', 3
    )'
))
LAYOUT(HASHED())
LIFETIME(0);  -- Static data, never reload

-- ============================================================================
-- CATEGORY METADATA DICTIONARY
-- ============================================================================
-- Product category enrichment

CREATE DICTIONARY IF NOT EXISTS dict_category_metadata
(
    category String,
    category_display String,
    parent_category String,
    commission_rate Decimal(5,2)
)
PRIMARY KEY category
SOURCE(CLICKHOUSE(
    QUERY 'SELECT * FROM (
        SELECT ''Electronics'' AS category, ''Electronics & Gadgets'' AS category_display, ''Tech'' AS parent_category, 5.0 AS commission_rate
        UNION ALL SELECT ''Clothing'', ''Clothing & Fashion'', ''Retail'', 10.0
        UNION ALL SELECT ''Books'', ''Books & Media'', ''Retail'', 8.0
        UNION ALL SELECT ''Home & Garden'', ''Home & Garden'', ''Retail'', 7.0
        UNION ALL SELECT ''Sports'', ''Sports & Outdoors'', ''Retail'', 9.0
        UNION ALL SELECT ''Beauty'', ''Beauty & Personal Care'', ''Retail'', 12.0
        UNION ALL SELECT ''Toys'', ''Toys & Games'', ''Retail'', 10.0
        UNION ALL SELECT ''Automotive'', ''Automotive & Tools'', ''Tech'', 6.0
        UNION ALL SELECT ''Health'', ''Health & Wellness'', ''Retail'', 11.0
        UNION ALL SELECT ''Food'', ''Food & Beverage'', ''Retail'', 15.0
    )'
))
LAYOUT(HASHED())
LIFETIME(0);

-- ============================================================================
-- HOW TO USE DICTIONARIES
-- ============================================================================

-- Example 1: Enrich events with user country without JOIN
-- Traditional (slow):
-- SELECT e.*, u.country FROM events e JOIN users u ON e.user_id = u.user_id

-- With dictionary (fast):
-- SELECT
--     e.*,
--     dictGet('dict_users', 'country', e.user_id) as country,
--     dictGet('dict_users', 'is_premium', e.user_id) as is_premium
-- FROM events e
-- WHERE event_date = today()

-- Example 2: Enrich orders with product details
-- SELECT
--     o.*,
--     dictGet('dict_products', 'product_name', o.product_id) as product_name,
--     dictGet('dict_products', 'category', o.product_id) as category,
--     dictGet('dict_products', 'price', o.product_id) as product_price
-- FROM orders o
-- WHERE order_date = today()

-- Example 3: Multi-level enrichment with geographic data
-- SELECT
--     e.event_id,
--     e.user_id,
--     dictGet('dict_users', 'country', e.user_id) as country_code,
--     dictGet('dict_country_metadata', 'country_name', country_code) as country_name,
--     dictGet('dict_country_metadata', 'region', country_code) as region,
--     dictGet('dict_country_metadata', 'continent', country_code) as continent,
--     e.event_type,
--     e.revenue
-- FROM events e
-- WHERE event_date >= today() - INTERVAL 7 DAY

-- Example 4: Product category enrichment
-- SELECT
--     p.product_id,
--     p.product_name,
--     p.category,
--     dictGet('dict_category_metadata', 'category_display', p.category) as category_display,
--     dictGet('dict_category_metadata', 'parent_category', p.category) as parent_category,
--     dictGet('dict_category_metadata', 'commission_rate', p.category) as commission_rate,
--     sum(o.total_amount) as revenue,
--     sum(o.total_amount) * commission_rate / 100 as estimated_commission
-- FROM orders o
-- JOIN products p ON o.product_id = p.product_id
-- WHERE o.status = 'completed'
-- GROUP BY p.product_id, p.product_name, p.category
-- ORDER BY revenue DESC
-- LIMIT 20

-- ============================================================================
-- DICTIONARY LAYOUTS
-- ============================================================================
-- HASHED() - Hash table in memory, O(1) lookup, all data in RAM
-- SPARSE_HASHED() - Sparse hash, uses less memory but slightly slower
-- FLAT() - Array indexed by key, fastest but requires contiguous keys
-- RANGE_HASHED() - For range-based lookups
-- CACHE() - LRU cache, only active subset in memory
-- COMPLEX_KEY_HASHED() - For composite keys
-- ============================================================================

-- ============================================================================
-- BENEFITS OF DICTIONARIES
-- ============================================================================
-- 1. Performance: O(1) lookups vs O(log n) for JOINs
-- 2. Memory efficient: Cached in RAM, shared across queries
-- 3. Automatic refresh: LIFETIME controls reload frequency
-- 4. No query planning: Instant lookup, no JOIN optimization needed
-- 5. Cross-database: Can source from external databases
--
-- Use dictionaries when:
-- - Dimension tables are relatively small (<10M rows)
-- - Lookup pattern is key → attributes
-- - Same dimensions used across many queries
-- - Need maximum performance for enrichment
--
-- Use JOINs when:
-- - Dimension tables are very large
-- - Complex join conditions
-- - Ad-hoc queries with varying join patterns
-- ============================================================================

-- ============================================================================
-- CHECK DICTIONARY STATUS
-- ============================================================================
-- To see all dictionaries:
-- SELECT * FROM system.dictionaries;

-- To check dictionary size and hit rate:
-- SELECT
--     name,
--     status,
--     element_count,
--     load_factor,
--     bytes_allocated,
--     query_count,
--     hit_rate,
--     last_successful_update_time
-- FROM system.dictionaries
-- WHERE database = 'demo_db';

-- To force dictionary reload:
-- SYSTEM RELOAD DICTIONARY dict_users;
-- ============================================================================

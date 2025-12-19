# ClickHouse Real-Time Analytics Architecture

## System Overview

This document provides a visual architecture of the ClickHouse real-time analytics system, showing data flow from ingestion through storage to queries.

## Data Flow Architecture

```mermaid
graph TB
    subgraph "Data Ingestion Layer"
        A1[Real-Time Streamer<br/>100 events/sec<br/>20 orders/sec] --> |HTTP POST| CH[ClickHouse Server]
        A2[Batch Data Generator<br/>Initial 10K users<br/>1K products] --> |HTTP POST| CH
    end

    subgraph "Base Tables Layer"
        CH --> T1[(users<br/>MergeTree<br/>10K rows<br/>1.06 MiB)]
        CH --> T2[(products<br/>MergeTree<br/>1K rows<br/>23.53 KiB)]
        CH --> T3[(events<br/>MergeTree<br/>294K+ rows<br/>61.75 MiB<br/>PARTITION BY toYYYYMM)]
        CH --> T4[(orders<br/>MergeTree<br/>30K+ rows<br/>1.94 MiB<br/>PARTITION BY toYYYYMM)]
    end

    subgraph "Optimization Layer"
        T1 -.->|LowCardinality<br/>Compression: T64, Delta, ZSTD| T1
        T2 -.->|LowCardinality<br/>ORDER BY category| T2
        T3 -.->|14 Indices<br/>8 Projections<br/>TTL: 90 days| T3
        T4 -.->|Indices<br/>Projections<br/>TTL: 1 year| T4
    end

    subgraph "Materialized Views Layer - Auto-Update on INSERT"
        T3 -->|Auto-Update| MV1[mv_hourly_events<br/>SummingMergeTree<br/>383K rows<br/>4.45 MiB]
        T3 -->|Auto-Update| MV2[mv_user_funnel<br/>AggregatingMergeTree<br/>468K rows<br/>2.41 MiB]
        T3 -->|Auto-Update| MV3[mv_country_stats<br/>SummingMergeTree<br/>1.8K rows<br/>23.80 KiB]
        T3 -->|Auto-Update| MV4[daily_user_activity<br/>SummingMergeTree<br/>468K rows<br/>4.61 MiB]
        T4 -->|Auto-Update| MV5[mv_product_revenue<br/>SummingMergeTree<br/>26K rows<br/>376.34 KiB]
    end

    subgraph "Query Access Patterns"
        MV1 --> Q1[Hourly Analytics<br/>event_count, unique_users<br/>10-100x faster]
        MV2 --> Q2[Conversion Funnel<br/>page_views → cart → purchase<br/>Uses -Merge functions]
        MV3 --> Q3[Geographic Analytics<br/>events by country<br/>Pre-aggregated]
        MV4 --> Q4[User Activity<br/>Daily engagement metrics]
        MV5 --> Q5[Product Revenue<br/>total_revenue, order_count<br/>No JOIN needed]

        T1 --> Q6[User Lookups<br/>Uses proj_by_registration<br/>Uses idx_user_country]
        T3 --> Q7[Real-Time Events<br/>Uses proj_by_user<br/>Uses idx_event_type]
        T4 --> Q8[Order History<br/>Uses proj_by_product<br/>Uses idx_status]
    end

    subgraph "Application Layer"
        Q1 --> APP1[Dashboard<br/>Port 3000<br/>Analytics API]
        Q2 --> APP1
        Q3 --> APP1
        Q4 --> APP1
        Q5 --> APP1

        Q1 --> APP2[Interactive Dashboard<br/>Port 3001<br/>Real-Time Updates]
        Q2 --> APP2
        Q3 --> APP2
        Q6 --> APP2
        Q7 --> APP2
        Q8 --> APP2
    end

    style A1 fill:#10b981,stroke:#059669,color:#fff
    style A2 fill:#10b981,stroke:#059669,color:#fff
    style CH fill:#667eea,stroke:#5568d3,color:#fff
    style T1 fill:#3b82f6,stroke:#2563eb,color:#fff
    style T2 fill:#3b82f6,stroke:#2563eb,color:#fff
    style T3 fill:#3b82f6,stroke:#2563eb,color:#fff
    style T4 fill:#3b82f6,stroke:#2563eb,color:#fff
    style MV1 fill:#f59e0b,stroke:#d97706,color:#fff
    style MV2 fill:#f59e0b,stroke:#d97706,color:#fff
    style MV3 fill:#f59e0b,stroke:#d97706,color:#fff
    style MV4 fill:#f59e0b,stroke:#d97706,color:#fff
    style MV5 fill:#f59e0b,stroke:#d97706,color:#fff
    style APP1 fill:#8b5cf6,stroke:#7c3aed,color:#fff
    style APP2 fill:#8b5cf6,stroke:#7c3aed,color:#fff
```

## Detailed Component Breakdown

### 1. Data Ingestion Layer

**Real-Time Streamer** (`stream_data_realtime.py`)
- Ingests 100 events/second + 20 orders/second
- Target: ~360,000 events/hour
- Uses HTTP POST to ClickHouse
- UTC timestamps for proper real-time queries

**Batch Generator** (`generate_data.py`)
- Initial data load: 10,000 users, 1,000 products
- Generates realistic historical data

### 2. Base Tables Layer

All tables use **MergeTree** engine with optimizations:

#### **users** Table
```sql
ENGINE = MergeTree()
ORDER BY (country, is_premium, user_id)
```
- **LowCardinality**: `country` column
- **Compression**: T64 for age, Delta for dates
- **Optimized for**: Country/premium filtering

#### **products** Table
```sql
ENGINE = MergeTree()
ORDER BY (category, product_id)
```
- **LowCardinality**: `category` column
- **Optimized for**: Category grouping

#### **events** Table (Primary fact table)
```sql
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_type, event_date, user_id, event_timestamp)
```
- **LowCardinality**: `event_type`, `device_type`, `browser`, `country`
- **Compression**: Delta for timestamps, T64 for integers
- **TTL**: 90 days automatic deletion
- **14 Data Skipping Indices**:
  - Bloom filters: session_id, page_url
  - MinMax: revenue, duration_seconds
  - Set: event_type, device_type, country
- **8 Projections** for alternate sort orders:
  - `proj_by_country`: ORDER BY (country, event_date, event_type)
  - `proj_by_user`: ORDER BY (user_id, event_timestamp)
  - `proj_by_timestamp`: ORDER BY (event_timestamp, event_type)
  - `proj_daily_stats`: Pre-aggregated statistics

#### **orders** Table
```sql
ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (status, order_date, user_id, order_timestamp)
```
- **LowCardinality**: `status`, `payment_method`
- **TTL**: 1 year retention
- **Projections**: By user, by product, by amount

### 3. Materialized Views Layer

All MVs **auto-update** on every INSERT to base tables:

#### **mv_hourly_events** (SummingMergeTree)
```sql
GROUP BY event_date, event_hour, event_type
Aggregates: event_count, unique_users, total_revenue
```
- **Query Speedup**: 10-100x faster than raw events
- **Use Case**: Hourly analytics dashboards

#### **mv_user_funnel** (AggregatingMergeTree)
```sql
GROUP BY user_id, event_date
Uses: countState(), sumState() with -Merge combinators
```
- **Special Engine**: Stores intermediate aggregate states
- **Query Pattern**: Use `countMerge()`, `sumMerge()` to finalize
- **Use Case**: Conversion funnel analysis

#### **mv_country_stats** (SummingMergeTree)
```sql
GROUP BY country, event_date
Aggregates: event_count, unique_users, revenue, purchase_count
```
- **Use Case**: Geographic breakdown

#### **daily_user_activity** (SummingMergeTree)
```sql
GROUP BY user_id, activity_date
Aggregates: activity_count, event_types_used
```
- **Use Case**: User engagement tracking

#### **mv_product_revenue** (SummingMergeTree)
```sql
GROUP BY product_id, order_date, status
Aggregates: order_count, total_revenue, total_quantity, avg_order_value
```
- **Performance Benefit**: Eliminates expensive JOINs
- **Use Case**: Product performance dashboard

### 4. Query Access Patterns

#### Pattern 1: Direct MV Queries (10-100x faster)
```sql
-- Fast hourly stats
SELECT event_date, event_hour, SUM(event_count)
FROM mv_hourly_events
WHERE event_date >= today() - 7
GROUP BY event_date, event_hour
```

#### Pattern 2: AggregatingMergeTree with -Merge
```sql
-- Conversion funnel
WITH agg AS (
    SELECT
        countMerge(total_events) as total,
        sumMerge(page_views) as views,
        sumMerge(purchases) as purchases
    FROM mv_user_funnel
    WHERE event_date >= today() - 30
)
SELECT *, purchases * 100.0 / views as conversion_rate
FROM agg
```

#### Pattern 3: Real-Time Queries with Projections
```sql
-- User timeline (uses proj_by_user automatically)
SELECT event_type, event_timestamp, revenue
FROM events
WHERE user_id = 1234
ORDER BY event_timestamp DESC
LIMIT 50
```

#### Pattern 4: Geographic Queries with Indices
```sql
-- Country filtering (uses idx_country set index)
SELECT event_type, count() as count
FROM events
WHERE country IN ('US', 'UK', 'DE')
AND event_date >= today()
GROUP BY event_type
```

### 5. Application Layer

#### **Dashboard** (Port 3000)
- `/api/stats` - Overall statistics
- `/api/top-products` - Uses `mv_product_revenue`
- `/api/conversion-funnel` - Uses `mv_user_funnel`
- `/api/hourly-activity` - Uses `mv_hourly_events`
- `/api/revenue-trend` - Monthly trends
- `/api/user-segments` - User segmentation

#### **Interactive Dashboard** (Port 3001)
- Real-time event stream (Server-Sent Events)
- Live metrics cards (updates every 2-3 seconds)
- Interactive charts (Chart.js)
- Query builder (read-only SELECT)
- Geographic breakdown
- Top active users

## Performance Characteristics

### Data Ingestion
- **Throughput**: ~100 events/sec, ~20 orders/sec
- **Compression**: 2.92x average ratio
- **Latency**: <100ms for INSERT

### Query Performance
- **MV Queries**: 10-100x faster than raw table scans
- **Projection Queries**: Automatic selection of optimal sort order
- **Index Queries**: Data skipping reduces granules scanned by 90%+

### Storage
- **Events**: 61.75 MiB for 294K rows (compressed)
- **MVs**: 4-5 MiB for pre-aggregated data
- **Total**: ~70 MiB for 300K+ events

## Data Flow Summary

1. **Ingestion** → Data enters via HTTP POST (real-time or batch)
2. **Storage** → Written to base tables (MergeTree)
3. **Auto-Aggregation** → Materialized views update automatically
4. **Optimization** → Indices, projections, compression applied
5. **Queries** → Applications access MVs for fast results
6. **Display** → Dashboards show real-time analytics

## Key Architectural Benefits

✅ **Real-Time Updates**: MVs update on every INSERT
✅ **Query Speed**: 10-100x faster with pre-aggregations
✅ **Storage Efficiency**: 2.92x compression ratio
✅ **Automatic Optimization**: Projections selected automatically
✅ **Data Lifecycle**: TTL manages retention automatically
✅ **Scalability**: Partitioned by month for easy management
✅ **Flexibility**: Multiple access patterns supported

## Technologies Used

- **ClickHouse 25.12.1**: Columnar OLAP database
- **Docker & Docker Compose**: Containerization
- **Python 3.9+**: Data generation and streaming
- **Flask**: Web application framework
- **Chart.js**: Real-time visualization
- **Server-Sent Events**: Live data streaming

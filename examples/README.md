# SQL Query Examples

This directory contains useful ClickHouse SQL queries for exploring the analytics demo data.

## 📊 Available Query Categories

### [sample_queries.sql](./sample_queries.sql)

**User Analytics**
- Top countries by user count
- Premium vs Regular user comparison
- User demographics analysis

**Event Analytics** 
- Daily event trends and patterns
- Most active users identification
- Event type distributions

**Revenue Analytics**
- Monthly revenue trends
- Top performing products
- Revenue by geographic regions

**Conversion Analytics**
- Conversion funnel analysis
- Page view to purchase rates
- User journey optimization

**Time-based Analytics**
- Hourly activity patterns
- Day of week performance
- Seasonal trends

**Advanced Analytics**
- Customer Lifetime Value (CLV)
- Cohort analysis and retention
- Product affinity analysis

## 🚀 How to Use

### Option 1: ClickHouse HTTP Interface
```bash
# Copy any query and run via HTTP
curl -X POST 'http://localhost:8123/' \
  --user 'demo_user:demo_password' \
  --data-binary "SELECT country, COUNT(*) FROM users GROUP BY country LIMIT 5"
```

### Option 2: AI Chat Interface
Visit `http://localhost:5001` and ask questions like:
- "What are the top 5 countries by revenue?"
- "Show me daily user activity trends"
- "Which products have the highest conversion rates?"

### Option 3: Copy-paste into Dashboard
Use the analytics dashboard at `http://localhost:3000` to explore data interactively.

## 📈 Sample Results

These queries work with the generated demo data:
- **500K+ events** across multiple event types
- **10K users** from 10 different countries  
- **1K products** in various categories
- **25K orders** with realistic transaction data

Perfect for demonstrating ClickHouse's analytical capabilities! 🎯

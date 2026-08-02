USE retail;

-- ----------------------------------------------------------------------------
-- Schema
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS customers;
CREATE TABLE customers AS
SELECT
    CAST(CustomerID AS UNSIGNED) AS customer_id,
    MIN(Country)                 AS country
FROM raw_retail
WHERE CustomerID IS NOT NULL AND CustomerID <> ''
GROUP BY CAST(CustomerID AS UNSIGNED);

ALTER TABLE customers ADD PRIMARY KEY (customer_id);

DROP TABLE IF EXISTS products;
CREATE TABLE products AS
SELECT
    CAST(StockCode AS CHAR(50)) AS stock_code,
    MIN(Description)            AS description,
    ROUND(AVG(CAST(Price AS DECIMAL(10,2))), 2) AS unit_price
FROM raw_retail
WHERE CAST(Price AS DECIMAL(10,2)) > 0
GROUP BY StockCode;

ALTER TABLE products ADD PRIMARY KEY (stock_code);

DROP TABLE IF EXISTS orders;
CREATE TABLE orders AS
SELECT
    CAST(Invoice AS CHAR(50))                            AS order_id,
    CAST(CustomerID AS UNSIGNED)                         AS customer_id,
    MIN(STR_TO_DATE(REPLACE(InvoiceDate, '/', '-'), '%d-%m-%Y %H:%i')) AS order_ts,
    CASE WHEN Invoice LIKE 'C%' THEN 1 ELSE 0 END        AS is_cancellation
FROM raw_retail
WHERE CustomerID IS NOT NULL AND CustomerID <> ''
GROUP BY Invoice, CAST(CustomerID AS UNSIGNED),
         CASE WHEN Invoice LIKE 'C%' THEN 1 ELSE 0 END;

ALTER TABLE orders ADD PRIMARY KEY (order_id);
ALTER TABLE orders ADD INDEX idx_orders_cust_ts (customer_id, order_ts);

DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items AS
SELECT
    CAST(Invoice AS CHAR(50))      AS order_id,
    CAST(StockCode AS CHAR(50))    AS stock_code,
    CAST(Quantity AS SIGNED)       AS quantity,
    CAST(Price AS DECIMAL(10,2))   AS unit_price,
    ROUND(CAST(Quantity AS SIGNED) * CAST(Price AS DECIMAL(10,2)), 2) AS line_revenue
FROM raw_retail
WHERE CustomerID IS NOT NULL AND CustomerID <> ''
  AND CAST(Price AS DECIMAL(10,2)) > 0;

ALTER TABLE order_items ADD INDEX idx_items_order (order_id);

-- ----------------------------------------------------------------------------
-- Cohort retention
-- ----------------------------------------------------------------------------
WITH first_purchase AS (
    SELECT customer_id, DATE_FORMAT(MIN(order_ts), '%Y-%m-01') AS cohort_month
    FROM orders WHERE is_cancellation = 0 GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT customer_id, DATE_FORMAT(order_ts, '%Y-%m-01') AS activity_month
    FROM orders WHERE is_cancellation = 0
),
cohort_activity AS (
    SELECT f.cohort_month, TIMESTAMPDIFF(MONTH, f.cohort_month, a.activity_month) AS month_index, a.customer_id
    FROM activity a JOIN first_purchase f ON f.customer_id = a.customer_id
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS n_customers FROM first_purchase GROUP BY cohort_month
)
SELECT
    ca.cohort_month, cs.n_customers AS cohort_size, ca.month_index,
    COUNT(DISTINCT ca.customer_id) AS active_customers,
    ROUND(100.0 * COUNT(DISTINCT ca.customer_id) / cs.n_customers, 1) AS retention_pct
FROM cohort_activity ca
JOIN cohort_size cs ON cs.cohort_month = ca.cohort_month
GROUP BY ca.cohort_month, cs.n_customers, ca.month_index
ORDER BY ca.cohort_month, ca.month_index;

-- ----------------------------------------------------------------------------
-- RFM segmentation
-- ----------------------------------------------------------------------------
WITH customer_metrics AS (
    SELECT o.customer_id, DATEDIFF((SELECT MAX(order_ts) FROM orders), MAX(o.order_ts)) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency, SUM(oi.line_revenue) AS monetary
    FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY o.customer_id HAVING SUM(oi.line_revenue) > 0
),
rfm_scores AS (
    SELECT customer_id, frequency, monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM customer_metrics
),
segmented AS (
    SELECT *,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal'
            WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
            WHEN r_score <= 2 AND f_score >= 4                  THEN 'At Risk'
            WHEN r_score <= 2 AND f_score <= 2                  THEN 'Hibernating'
            ELSE 'Needs Attention'
        END AS segment
    FROM rfm_scores
)
SELECT segment, COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_customers,
    ROUND(SUM(monetary), 0) AS total_revenue,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_revenue,
    ROUND(AVG(frequency), 1) AS avg_orders
FROM segmented GROUP BY segment ORDER BY total_revenue DESC;

-- ----------------------------------------------------------------------------
-- Purchase-lifecycle funnel
-- ----------------------------------------------------------------------------
WITH customer_orders AS (
    SELECT o.customer_id, COUNT(DISTINCT o.order_id) AS n_orders, SUM(oi.line_revenue) AS lifetime_value
    FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.is_cancellation = 0 GROUP BY o.customer_id
),
value_bands AS (
    SELECT *, NTILE(5) OVER (ORDER BY lifetime_value ASC) AS value_quintile FROM customer_orders
),
stages AS (
    SELECT 1 AS stage_no, 'Acquired (1st purchase)' AS stage, COUNT(*) AS customers FROM value_bands
    UNION ALL SELECT 2, 'Repeat buyer (2nd purchase)', COUNT(*) FROM value_bands WHERE n_orders >= 2
    UNION ALL SELECT 3, 'Established (3+ purchases)', COUNT(*) FROM value_bands WHERE n_orders >= 3
    UNION ALL SELECT 4, 'High value (top revenue quintile)', COUNT(*) FROM value_bands WHERE value_quintile = 5
)
SELECT stage_no, stage, customers,
    ROUND(100.0 * customers / FIRST_VALUE(customers) OVER (ORDER BY stage_no), 1) AS pct_of_top,
    ROUND(100.0 * customers / NULLIF(LAG(customers) OVER (ORDER BY stage_no), 0), 1) AS step_conversion_pct,
    ROUND(100.0 - 100.0 * customers / NULLIF(LAG(customers) OVER (ORDER BY stage_no), 0), 1) AS step_dropoff_pct
FROM stages ORDER BY stage_no;

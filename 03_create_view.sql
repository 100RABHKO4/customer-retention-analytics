USE retail;

DROP VIEW IF EXISTS v_customer_rfm;

CREATE VIEW v_customer_rfm AS
WITH customer_metrics AS (
    SELECT
        o.customer_id,
        DATEDIFF((SELECT MAX(order_ts) FROM orders), MAX(o.order_ts)) AS recency_days,
        COUNT(DISTINCT o.order_id)                                    AS frequency,
        SUM(oi.line_revenue)                                          AS monetary
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY o.customer_id
    HAVING SUM(oi.line_revenue) > 0
),
rfm_scores AS (
    SELECT
        customer_id, recency_days, frequency, ROUND(monetary, 2) AS monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency    ASC)  AS f_score,
        NTILE(5) OVER (ORDER BY monetary     ASC)  AS m_score
    FROM customer_metrics
)
SELECT
    customer_id, recency_days, frequency, monetary, r_score, f_score, m_score,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal'
        WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
        WHEN r_score <= 2 AND f_score >= 4                  THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2                  THEN 'Hibernating'
        ELSE 'Needs Attention'
    END AS segment
FROM rfm_scores;

SELECT * FROM v_customer_rfm ORDER BY monetary DESC LIMIT 10;

SELECT
    segment,
    COUNT(*)                                                     AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS pct_customers,
    ROUND(SUM(monetary), 0)                                      AS total_revenue,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_revenue
FROM v_customer_rfm
GROUP BY segment
ORDER BY total_revenue DESC;

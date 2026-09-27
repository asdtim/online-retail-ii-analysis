-- =============================================================================
-- 06_rfm_segmentation.sql : who are the valuable customers?
-- =============================================================================
-- RFM scores every registered customer with at least one sale on
--   Recency    days since the last sale invoice, measured at the snapshot date
--              (the day after the last transaction in the data: 10 Dec 2011)
--   Frequency  number of sale invoices
--   Monetary   net revenue (sales minus cancellations)
-- Each dimension is scored 1-5 by quintile of its value. Scores are assigned
-- with value thresholds instead of NTILE(), so customers with identical values
-- always get the same score (NTILE would split ties across two buckets).
-- Segments follow the usual Recency x FM grid, FM = rounded mean of F and M.
-- =============================================================================

CREATE OR REPLACE TABLE rpt_rfm_customer AS
WITH snapshot AS (
    SELECT max(invoice_date) + 1 AS snapshot_date FROM fact_invoice
),
base AS (
    SELECT i.customer_id,
           c.country,
           min(i.invoice_date) FILTER (WHERE NOT i.is_cancellation)   AS first_purchase_date,
           max(i.invoice_date) FILTER (WHERE NOT i.is_cancellation)   AS last_purchase_date,
           count(*)            FILTER (WHERE NOT i.is_cancellation)   AS frequency,
           sum(i.invoice_value)                                       AS monetary
    FROM fact_invoice i
    JOIN dim_customer c USING (customer_id)
    WHERE i.customer_id IS NOT NULL
    GROUP BY i.customer_id, c.country
    HAVING count(*) FILTER (WHERE NOT i.is_cancellation) > 0
),
with_recency AS (
    SELECT b.*,
           date_diff('day', b.last_purchase_date, s.snapshot_date) AS recency_days
    FROM base b, snapshot s
),
thresholds AS (
    -- quintile boundaries of each measure (DuckDB lists are 1-indexed)
    SELECT quantile_cont(recency_days, [0.2, 0.4, 0.6, 0.8]) AS r_q,
           quantile_cont(frequency,    [0.2, 0.4, 0.6, 0.8]) AS f_q,
           quantile_cont(monetary,     [0.2, 0.4, 0.6, 0.8]) AS m_q
    FROM with_recency
),
scored AS (
    SELECT w.*,
           -- recency: fewer days is better, so the lowest quintile scores 5
           CASE WHEN recency_days <= r_q[1] THEN 5 WHEN recency_days <= r_q[2] THEN 4
                WHEN recency_days <= r_q[3] THEN 3 WHEN recency_days <= r_q[4] THEN 2 ELSE 1 END AS r_score,
           CASE WHEN frequency > f_q[4] THEN 5 WHEN frequency > f_q[3] THEN 4
                WHEN frequency > f_q[2] THEN 3 WHEN frequency > f_q[1] THEN 2 ELSE 1 END AS f_score,
           CASE WHEN monetary > m_q[4] THEN 5 WHEN monetary > m_q[3] THEN 4
                WHEN monetary > m_q[2] THEN 3 WHEN monetary > m_q[1] THEN 2 ELSE 1 END AS m_score
    FROM with_recency w, thresholds t
),
segmented AS (
    SELECT *,
           CAST(round((f_score + m_score) / 2.0) AS INTEGER) AS fm_score
    FROM scored
)
SELECT customer_id,
       country,
       first_purchase_date,
       last_purchase_date,
       recency_days,
       frequency,
       round(monetary, 2)                        AS monetary,
       r_score, f_score, m_score, fm_score,
       r_score || f_score || m_score             AS rfm_cell,
       CASE
           WHEN r_score >= 4 AND fm_score >= 4 THEN 'Champions'
           WHEN r_score >= 3 AND fm_score >= 3 THEN 'Loyal Customers'
           WHEN r_score >= 4 AND fm_score  = 2 THEN 'Potential Loyalists'
           WHEN r_score  = 5 AND fm_score  = 1 THEN 'New Customers'
           WHEN r_score  = 4 AND fm_score  = 1 THEN 'Promising'
           WHEN r_score  = 3 AND fm_score  = 2 THEN 'Need Attention'
           WHEN r_score  = 3 AND fm_score  = 1 THEN 'About to Sleep'
           WHEN r_score <= 2 AND fm_score  = 5 THEN 'Cannot Lose Them'
           WHEN r_score <= 2 AND fm_score >= 3 THEN 'At Risk'
           WHEN r_score  = 2                   THEN 'Hibernating'
           ELSE 'Lost'
       END AS segment
FROM segmented
ORDER BY customer_id;

-- Quintile thresholds actually used (frequency is heavily skewed: most customers order once or twice)
WITH b AS (SELECT recency_days, frequency, monetary FROM rpt_rfm_customer)
SELECT 'recency_days' AS measure, quantile_cont(recency_days, [0.2, 0.4, 0.6, 0.8]) AS quintile_boundaries FROM b
UNION ALL SELECT 'frequency', quantile_cont(frequency, [0.2, 0.4, 0.6, 0.8]) FROM b
UNION ALL SELECT 'monetary',  quantile_cont(monetary,  [0.2, 0.4, 0.6, 0.8]) FROM b;

-- Segment summary: size and value of each segment
CREATE OR REPLACE TABLE rpt_rfm_segment AS
SELECT segment,
       count(*)                                                        AS customers,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)              AS pct_customers,
       round(sum(monetary))                                            AS net_revenue,
       round(100.0 * sum(monetary) / sum(sum(monetary)) OVER (), 1)    AS pct_revenue,
       round(avg(recency_days))                                        AS avg_recency_days,
       round(avg(frequency), 1)                                        AS avg_orders,
       round(avg(monetary))                                            AS avg_net_revenue,
       round(sum(monetary) / count(*))                                 AS revenue_per_customer
FROM rpt_rfm_customer
GROUP BY segment
ORDER BY net_revenue DESC;

SELECT * FROM rpt_rfm_segment;

-- Concentration: share of revenue from the top 10% / 20% of customers by net revenue
WITH ranked AS (
    SELECT monetary,
           percent_rank() OVER (ORDER BY monetary DESC) AS pr
    FROM rpt_rfm_customer
)
SELECT round(100.0 * sum(monetary) FILTER (WHERE pr <= 0.10) / sum(monetary), 1) AS top_10pct_customers_revenue_share,
       round(100.0 * sum(monetary) FILTER (WHERE pr <= 0.20) / sum(monetary), 1) AS top_20pct_customers_revenue_share
FROM ranked;

-- Segment mix by region
SELECT c.region,
       r.segment,
       count(*) AS customers
FROM rpt_rfm_customer r
JOIN dim_country c USING (country)
GROUP BY c.region, r.segment
ORDER BY c.region, customers DESC;

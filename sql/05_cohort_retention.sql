-- =============================================================================
-- 05_cohort_retention.sql : do customers come back?
-- =============================================================================
-- Method (classic monthly cohort analysis)
--   1. cohort_month  = month of a customer's first sale invoice (dim_customer)
--   2. a customer is "active" in a month if they placed >= 1 sale invoice in it
--   3. period_number = months between the cohort month and the active month
--   4. retention     = active customers in period k / cohort size
-- Only registered customers can be tracked (guest checkouts have no id).
--
-- Caveat: the data starts on 1 Dec 2009, so the Dec 2009 "cohort" is really
-- every existing customer who happened to order that month. Its retention is
-- much higher than a genuine new-customer cohort; read it separately.
-- Dec 2011 has only 9 days of data, so its cohort has period 0 only.
-- =============================================================================

CREATE OR REPLACE TABLE rpt_cohort_retention AS
WITH customer_months AS (
    SELECT DISTINCT customer_id, invoice_month
    FROM fact_invoice
    WHERE NOT is_cancellation AND customer_id IS NOT NULL
),
cohort_size AS (
    SELECT cohort_month, count(*) AS cohort_customers
    FROM dim_customer
    WHERE cohort_month IS NOT NULL
    GROUP BY cohort_month
),
activity AS (
    SELECT c.cohort_month,
           date_diff('month', c.cohort_month, m.invoice_month) AS period_number,
           count(DISTINCT m.customer_id)                       AS active_customers
    FROM customer_months m
    JOIN dim_customer c USING (customer_id)
    GROUP BY c.cohort_month, period_number
)
SELECT a.cohort_month,
       strftime(a.cohort_month, '%Y-%m')                                 AS cohort_label,
       s.cohort_customers,
       a.period_number,
       a.active_customers,
       round(100.0 * a.active_customers / s.cohort_customers, 1)         AS retention_pct
FROM activity a
JOIN cohort_size s USING (cohort_month)
ORDER BY a.cohort_month, a.period_number;

-- Retention matrix, months 0-12 (rows = cohort, columns = months since first purchase)
PIVOT (SELECT cohort_label, cohort_customers, period_number, retention_pct
       FROM rpt_cohort_retention WHERE period_number <= 12)
ON period_number
USING first(retention_pct)
GROUP BY cohort_label, cohort_customers
ORDER BY cohort_label;

-- Average retention curve, weighting each cohort by its size.
-- Only genuine new-customer cohorts (Jan 2010 onwards) with at least 12
-- observable months, so every cohort contributes to every period.
CREATE OR REPLACE TABLE rpt_retention_curve AS
SELECT period_number,
       count(DISTINCT cohort_month)                              AS cohorts,
       sum(active_customers)                                     AS active_customers,
       sum(cohort_customers)                                     AS cohort_customers,
       round(100.0 * sum(active_customers) / sum(cohort_customers), 1) AS retention_pct
FROM rpt_cohort_retention
WHERE cohort_month BETWEEN DATE '2010-01-01' AND DATE '2010-11-01'
  AND period_number <= 12
GROUP BY period_number
ORDER BY period_number;

-- The curve: how many of the 2010 new customers were still buying k months later
SELECT * FROM rpt_retention_curve;

-- Same curve for the left-censored Dec 2009 group, for comparison
SELECT period_number, cohort_customers, active_customers, retention_pct
FROM rpt_cohort_retention
WHERE cohort_month = DATE '2009-12-01' AND period_number <= 12
ORDER BY period_number;

-- Month 1 / 3 / 6 / 12 retention by cohort: are newer cohorts better or worse?
SELECT cohort_label,
       cohort_customers,
       max(retention_pct) FILTER (WHERE period_number = 1)  AS month_1_pct,
       max(retention_pct) FILTER (WHERE period_number = 3)  AS month_3_pct,
       max(retention_pct) FILTER (WHERE period_number = 6)  AS month_6_pct,
       max(retention_pct) FILTER (WHERE period_number = 12) AS month_12_pct
FROM rpt_cohort_retention
GROUP BY cohort_label, cohort_customers
ORDER BY cohort_label;

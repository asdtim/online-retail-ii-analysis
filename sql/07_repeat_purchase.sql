-- =============================================================================
-- 07_repeat_purchase.sql : how much of the business is repeat business?
-- =============================================================================
-- Definitions
--   order            a sale invoice
--   order day        a calendar day on which a customer placed >= 1 order
--                    (two invoices minutes apart are usually one basket split
--                    by the system, so repeat behaviour is measured in days)
--   repeat customer  registered customer with >= 2 order days
-- Repeat rates within a fixed window (90 / 180 / 365 days of the first order)
-- are only reported for cohorts old enough for the whole window to be visible,
-- otherwise recent cohorts would look artificially bad.
-- =============================================================================

-- One row per registered customer with first / second order day and order counts
CREATE OR REPLACE TABLE rpt_customer_orders AS
WITH order_days AS (
    SELECT customer_id, invoice_date,
           count(*)           AS orders_on_day,
           sum(invoice_value) AS value_on_day
    FROM fact_invoice
    WHERE NOT is_cancellation AND customer_id IS NOT NULL
    GROUP BY customer_id, invoice_date
),
ranked AS (
    SELECT *,
           row_number() OVER (PARTITION BY customer_id ORDER BY invoice_date) AS day_rank
    FROM order_days
)
SELECT r.customer_id,
       c.country,
       c.cohort_month,
       min(invoice_date)                                            AS first_order_date,
       min(invoice_date) FILTER (WHERE day_rank = 2)                AS second_order_date,
       date_diff('day', min(invoice_date), min(invoice_date) FILTER (WHERE day_rank = 2)) AS days_to_second_order,
       count(*)                                                     AS order_days,
       sum(orders_on_day)                                           AS orders,
       round(sum(value_on_day), 2)                                  AS gross_sales,
       count(*) >= 2                                                AS is_repeat_customer
FROM ranked r
JOIN dim_customer c USING (customer_id)
GROUP BY r.customer_id, c.country, c.cohort_month
ORDER BY r.customer_id;

-- Headline: one-time vs repeat customers and their share of sales
SELECT CASE WHEN is_repeat_customer THEN 'repeat (2+ order days)' ELSE 'one-time' END AS customer_type,
       count(*)                                                     AS customers,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)           AS pct_customers,
       round(sum(gross_sales))                                      AS gross_sales,
       round(100.0 * sum(gross_sales) / sum(sum(gross_sales)) OVER (), 1) AS pct_sales,
       round(avg(orders), 1)                                        AS avg_orders,
       round(avg(gross_sales))                                      AS avg_sales_per_customer
FROM rpt_customer_orders
GROUP BY 1
ORDER BY 1;

-- Distribution of order days per customer
CREATE OR REPLACE TABLE rpt_orders_per_customer AS
SELECT CASE WHEN order_days = 1 THEN '1'
            WHEN order_days = 2 THEN '2'
            WHEN order_days BETWEEN 3 AND 5 THEN '3-5'
            WHEN order_days BETWEEN 6 AND 10 THEN '6-10'
            WHEN order_days BETWEEN 11 AND 20 THEN '11-20'
            ELSE '21+' END                                          AS order_days_band,
       min(order_days)                                              AS band_sort,
       count(*)                                                     AS customers,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)           AS pct_customers,
       round(sum(gross_sales))                                      AS gross_sales,
       round(100.0 * sum(gross_sales) / sum(sum(gross_sales)) OVER (), 1) AS pct_sales
FROM rpt_customer_orders
GROUP BY 1
ORDER BY band_sort;

SELECT * FROM rpt_orders_per_customer;

-- How long until the second order? (repeat customers only)
SELECT count(*)                                              AS repeat_customers,
       round(quantile_cont(days_to_second_order, 0.25))      AS p25_days,
       round(quantile_cont(days_to_second_order, 0.50))      AS median_days,
       round(quantile_cont(days_to_second_order, 0.75))      AS p75_days,
       round(100.0 * count(*) FILTER (WHERE days_to_second_order <= 30)  / count(*), 1) AS pct_within_30d,
       round(100.0 * count(*) FILTER (WHERE days_to_second_order <= 90)  / count(*), 1) AS pct_within_90d,
       round(100.0 * count(*) FILTER (WHERE days_to_second_order <= 180) / count(*), 1) AS pct_within_180d
FROM rpt_customer_orders
WHERE is_repeat_customer;

-- Repeat rate within a fixed window, by acquisition cohort (only where the window is fully observable)
CREATE OR REPLACE TABLE rpt_repeat_by_cohort AS
WITH last_day AS (SELECT max(invoice_date) AS last_date FROM fact_invoice)
SELECT strftime(cohort_month, '%Y-%m')                       AS cohort_label,
       cohort_month,
       count(*)                                              AS customers,
       CASE WHEN cohort_month + INTERVAL 1 MONTH + INTERVAL 90 DAY  <= (SELECT last_date FROM last_day)
            THEN round(100.0 * count(*) FILTER (WHERE days_to_second_order <= 90)  / count(*), 1) END AS repeat_within_90d_pct,
       CASE WHEN cohort_month + INTERVAL 1 MONTH + INTERVAL 180 DAY <= (SELECT last_date FROM last_day)
            THEN round(100.0 * count(*) FILTER (WHERE days_to_second_order <= 180) / count(*), 1) END AS repeat_within_180d_pct,
       CASE WHEN cohort_month + INTERVAL 1 MONTH + INTERVAL 365 DAY <= (SELECT last_date FROM last_day)
            THEN round(100.0 * count(*) FILTER (WHERE days_to_second_order <= 365) / count(*), 1) END AS repeat_within_365d_pct
FROM rpt_customer_orders
GROUP BY cohort_month
ORDER BY cohort_month;

SELECT * FROM rpt_repeat_by_cohort;

-- Repeat rate by region (customers acquired before Dec 2010, so everyone has >= 12 months to come back)
SELECT c.region,
       count(*)                                                                  AS customers,
       round(100.0 * count(*) FILTER (WHERE o.days_to_second_order <= 365) / count(*), 1) AS repeat_within_365d_pct
FROM rpt_customer_orders o
JOIN dim_country c USING (country)
WHERE o.cohort_month BETWEEN DATE '2010-01-01' AND DATE '2010-11-01'
GROUP BY c.region
ORDER BY customers DESC;

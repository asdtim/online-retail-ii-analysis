-- =============================================================================
-- 04_monthly_sales.sql : how is the business trending?
-- =============================================================================
-- Definitions used everywhere in this project
--   gross_sales      value of sale lines (invoices without a 'C' prefix)
--   cancellations    value of cancellation lines, shown as a negative number
--   net_revenue      gross_sales + cancellations
--   orders           number of sale invoices
--   active_customers registered customers with at least one sale invoice in the month
--   new_customers    customers whose first-ever sale falls in the month
-- Guest (no customer id) lines count in revenue and orders but not in customer counts.
-- The data set runs 1 Dec 2009 - 9 Dec 2011, so Dec 2011 is a partial month.
-- =============================================================================

CREATE OR REPLACE TABLE rpt_monthly_sales AS
WITH monthly AS (
    SELECT i.invoice_month,
           sum(l.line_value)  FILTER (WHERE NOT i.is_cancellation)  AS gross_sales,
           sum(l.line_value)  FILTER (WHERE i.is_cancellation)      AS cancellations,
           sum(l.line_value)                                        AS net_revenue,
           sum(l.quantity)    FILTER (WHERE NOT i.is_cancellation)  AS units_sold,
           count(DISTINCT i.invoice)     FILTER (WHERE NOT i.is_cancellation) AS orders,
           count(DISTINCT i.invoice)     FILTER (WHERE i.is_cancellation)     AS cancellation_notes,
           count(DISTINCT i.customer_id) FILTER (WHERE NOT i.is_cancellation) AS active_customers
    FROM fact_invoice_line l
    JOIN fact_invoice i USING (invoice)
    GROUP BY i.invoice_month
),
new_customers AS (
    SELECT cohort_month AS invoice_month, count(*) AS new_customers
    FROM dim_customer
    WHERE cohort_month IS NOT NULL
    GROUP BY cohort_month
)
SELECT m.invoice_month,
       strftime(m.invoice_month, '%Y-%m')                         AS month_label,
       m.invoice_month < DATE '2011-12-01'                        AS is_complete_month,
       round(m.gross_sales, 2)                                    AS gross_sales,
       round(m.cancellations, 2)                                  AS cancellations,
       round(m.net_revenue, 2)                                    AS net_revenue,
       m.units_sold,
       m.orders,
       m.cancellation_notes,
       m.active_customers,
       coalesce(n.new_customers, 0)                               AS new_customers,
       m.active_customers - coalesce(n.new_customers, 0)          AS returning_customers,
       round(m.gross_sales / m.orders, 2)                         AS avg_order_value,
       round(100.0 * -m.cancellations / m.gross_sales, 2)         AS cancellation_rate_pct,
       round(100.0 * (m.net_revenue / lag(m.net_revenue, 12) OVER (ORDER BY m.invoice_month) - 1), 1) AS yoy_net_revenue_pct
FROM monthly m
LEFT JOIN new_customers n USING (invoice_month)
ORDER BY m.invoice_month;

-- Monthly trend (all months)
SELECT month_label, is_complete_month, gross_sales, cancellations, net_revenue, orders, active_customers,
       new_customers, avg_order_value, cancellation_rate_pct, yoy_net_revenue_pct
FROM rpt_monthly_sales
ORDER BY invoice_month;

-- Like-for-like years: Dec 2009-Nov 2010 vs Dec 2010-Nov 2011 (the two complete 12-month windows)
SELECT CASE WHEN invoice_month < DATE '2010-12-01' THEN 'Dec 2009 - Nov 2010' ELSE 'Dec 2010 - Nov 2011' END AS window_12m,
       round(sum(net_revenue))                  AS net_revenue,
       sum(orders)                              AS orders,
       round(sum(gross_sales) / sum(orders), 2) AS avg_order_value,
       sum(new_customers)                       AS new_customers,
       round(100.0 * -sum(cancellations) / sum(gross_sales), 2) AS cancellation_rate_pct
FROM rpt_monthly_sales
WHERE is_complete_month
GROUP BY 1
ORDER BY 1;

-- Seasonality: share of annual net revenue by calendar month, averaged over the two complete years
SELECT month(invoice_month)                                                       AS calendar_month,
       round(avg(net_revenue))                                                    AS avg_net_revenue,
       round(100.0 * avg(net_revenue) / (SELECT sum(net_revenue) / 2 FROM rpt_monthly_sales WHERE is_complete_month), 1) AS pct_of_annual_revenue
FROM rpt_monthly_sales
WHERE is_complete_month
GROUP BY 1
ORDER BY 1;

-- Region split by month (for the dashboard)
CREATE OR REPLACE TABLE rpt_monthly_sales_by_region AS
SELECT i.invoice_month,
       strftime(i.invoice_month, '%Y-%m')         AS month_label,
       c.region,
       round(sum(l.line_value), 2)                AS net_revenue,
       count(DISTINCT i.invoice) FILTER (WHERE NOT i.is_cancellation) AS orders
FROM fact_invoice_line l
JOIN fact_invoice i USING (invoice)
JOIN dim_country  c USING (country)
GROUP BY i.invoice_month, c.region
ORDER BY i.invoice_month, c.region;

-- Non-UK share of net revenue by 12-month window
SELECT CASE WHEN invoice_month < DATE '2010-12-01' THEN 'Dec 2009 - Nov 2010' ELSE 'Dec 2010 - Nov 2011' END AS window_12m,
       round(100.0 * sum(net_revenue) FILTER (WHERE region <> 'United Kingdom') / sum(net_revenue), 1) AS non_uk_share_pct
FROM rpt_monthly_sales_by_region
WHERE invoice_month < DATE '2011-12-01'
GROUP BY 1
ORDER BY 1;

-- When do customers order? Orders by weekday and hour
CREATE OR REPLACE TABLE rpt_orders_by_weekday_hour AS
SELECT dayofweek(invoice_ts)                    AS weekday_num,   -- 0 = Sunday
       strftime(invoice_ts, '%a')               AS weekday,
       hour(invoice_ts)                         AS hour_of_day,
       count(*)                                 AS orders,
       round(sum(invoice_value))                AS gross_sales
FROM fact_invoice
WHERE NOT is_cancellation
GROUP BY ALL
ORDER BY weekday_num, hour_of_day;

-- Orders by weekday (the retailer does not trade on Saturdays)
SELECT weekday, sum(orders) AS orders,
       round(100.0 * sum(orders) / (SELECT sum(orders) FROM rpt_orders_by_weekday_hour), 1) AS pct_orders
FROM rpt_orders_by_weekday_hour
GROUP BY weekday_num, weekday
ORDER BY weekday_num;

-- =============================================================================
-- 09_country_analysis.sql : where does the money come from?
-- =============================================================================
-- country comes from the invoice header; region is the grouping in dim_country
-- (United Kingdom / Europe ex UK / Rest of world / Unspecified).
-- Per-customer figures use registered customers only, because guest checkouts
-- cannot be counted as customers.
-- =============================================================================

CREATE OR REPLACE TABLE rpt_country AS
SELECT c.country,
       c.region,
       round(sum(l.line_value), 2)                                             AS net_revenue,
       round(100.0 * sum(l.line_value) / sum(sum(l.line_value)) OVER (), 2)    AS pct_net_revenue,
       count(DISTINCT i.invoice)     FILTER (WHERE NOT i.is_cancellation)      AS orders,
       count(DISTINCT i.customer_id) FILTER (WHERE NOT i.is_cancellation)      AS customers,
       round(sum(l.line_value) FILTER (WHERE NOT i.is_cancellation)
             / count(DISTINCT i.invoice) FILTER (WHERE NOT i.is_cancellation), 2) AS avg_order_value,
       round(sum(l.line_value) FILTER (WHERE i.customer_id IS NOT NULL)
             / nullif(count(DISTINCT i.customer_id) FILTER (WHERE NOT i.is_cancellation), 0), 2) AS net_revenue_per_customer,
       round(100.0 * -sum(l.line_value) FILTER (WHERE i.is_cancellation)
                   /  sum(l.line_value) FILTER (WHERE NOT i.is_cancellation), 2) AS cancellation_rate_pct
FROM fact_invoice_line l
JOIN fact_invoice i USING (invoice)
JOIN dim_country  c USING (country)
GROUP BY c.country, c.region
ORDER BY net_revenue DESC;

-- Top 15 countries
SELECT country, region, net_revenue, pct_net_revenue, orders, customers, avg_order_value, net_revenue_per_customer
FROM rpt_country
ORDER BY net_revenue DESC
LIMIT 15;

-- Region roll-up: the UK is ~85% of revenue, but overseas customers are worth more each
SELECT region,
       round(sum(net_revenue))                                            AS net_revenue,
       round(100.0 * sum(net_revenue) / sum(sum(net_revenue)) OVER (), 1) AS pct_net_revenue,
       sum(orders)                                                        AS orders,
       sum(customers)                                                     AS customers,
       round(sum(net_revenue) / sum(orders), 2)                           AS avg_order_value,
       round(sum(net_revenue) / nullif(sum(customers), 0))                AS net_revenue_per_customer
FROM rpt_country
GROUP BY region
ORDER BY net_revenue DESC;

-- Year-on-year growth by country (the two complete 12-month windows), top overseas markets
CREATE OR REPLACE TABLE rpt_country_growth AS
WITH windows AS (
    SELECT i.country,
           sum(l.line_value) FILTER (WHERE i.invoice_month BETWEEN DATE '2009-12-01' AND DATE '2010-11-01') AS revenue_y1,
           sum(l.line_value) FILTER (WHERE i.invoice_month BETWEEN DATE '2010-12-01' AND DATE '2011-11-01') AS revenue_y2
    FROM fact_invoice_line l
    JOIN fact_invoice i USING (invoice)
    GROUP BY i.country
)
SELECT w.country,
       c.region,
       round(w.revenue_y1)                                        AS revenue_dec09_nov10,
       round(w.revenue_y2)                                        AS revenue_dec10_nov11,
       round(100.0 * (w.revenue_y2 / nullif(w.revenue_y1, 0) - 1), 1) AS growth_pct
FROM windows w
JOIN dim_country c USING (country)
ORDER BY w.revenue_y2 DESC NULLS LAST, w.country;

SELECT * FROM rpt_country_growth LIMIT 12;

-- Number of countries with at least 10 orders, and how many of them grew
SELECT count(*)                                            AS countries_with_10_plus_orders,
       count(*) FILTER (WHERE g.growth_pct > 0)            AS grew,
       count(*) FILTER (WHERE g.growth_pct <= 0)           AS shrank
FROM rpt_country_growth g
JOIN rpt_country r USING (country)
WHERE r.orders >= 10 AND g.revenue_dec09_nov10 > 0;

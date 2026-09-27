-- =============================================================================
-- 08_returns_analysis.sql : what comes back, and how fast?
-- =============================================================================
-- A cancellation invoice ('C' prefix) records goods credited back to the
-- customer. The file does not say which sale a cancellation refers to, so each
-- cancellation line is matched to the most recent earlier sale line of the same
-- customer and product (a self-join across the fact tables). The match gives
-- the time between sale and cancellation; it is not an exact audit trail.
--
--   return rate = cancelled value / gross sales value (both as positive numbers)
-- =============================================================================

-- Monthly return rate (from the monthly table built in 04)
SELECT month_label, gross_sales, -cancellations AS cancelled_value, cancellation_rate_pct,
       orders, cancellation_notes
FROM rpt_monthly_sales
ORDER BY invoice_month;

-- Return rate by region
SELECT c.region,
       round(sum(l.line_value)  FILTER (WHERE NOT i.is_cancellation))   AS gross_sales,
       round(-sum(l.line_value) FILTER (WHERE i.is_cancellation))       AS cancelled_value,
       round(100.0 * -sum(l.line_value) FILTER (WHERE i.is_cancellation)
                   /  sum(l.line_value) FILTER (WHERE NOT i.is_cancellation), 2) AS return_rate_pct
FROM fact_invoice_line l
JOIN fact_invoice i USING (invoice)
JOIN dim_country  c USING (country)
GROUP BY c.region
ORDER BY gross_sales DESC;

-- Product-level returns
CREATE OR REPLACE TABLE rpt_returns_by_product AS
WITH per_product AS (
    SELECT l.stock_code,
           sum(l.quantity)    FILTER (WHERE NOT i.is_cancellation) AS units_sold,
           -sum(l.quantity)   FILTER (WHERE i.is_cancellation)     AS units_returned,
           sum(l.line_value)  FILTER (WHERE NOT i.is_cancellation) AS gross_sales,
           -sum(l.line_value) FILTER (WHERE i.is_cancellation)     AS returned_value
    FROM fact_invoice_line l
    JOIN fact_invoice i USING (invoice)
    GROUP BY l.stock_code
)
SELECT p.stock_code,
       d.description,
       p.units_sold,
       coalesce(p.units_returned, 0)                                    AS units_returned,
       round(p.gross_sales, 2)                                          AS gross_sales,
       round(coalesce(p.returned_value, 0), 2)                          AS returned_value,
       round(100.0 * coalesce(p.units_returned, 0) / p.units_sold, 2)   AS unit_return_rate_pct,
       round(100.0 * coalesce(p.returned_value, 0) / p.gross_sales, 2)  AS value_return_rate_pct
FROM per_product p
JOIN dim_product d USING (stock_code)
WHERE p.units_sold > 0
ORDER BY p.stock_code;

-- Products with the most value returned
SELECT stock_code, description, units_sold, units_returned, gross_sales, returned_value, value_return_rate_pct
FROM rpt_returns_by_product
ORDER BY returned_value DESC
LIMIT 15;

-- Highest return rates among products that sold at least 1,000 units
SELECT stock_code, description, units_sold, units_returned, unit_return_rate_pct, returned_value
FROM rpt_returns_by_product
WHERE units_sold >= 1000
ORDER BY unit_return_rate_pct DESC
LIMIT 15;

-- Customers who return the most value
SELECT i.customer_id,
       c.country,
       round(sum(i.invoice_value)  FILTER (WHERE NOT i.is_cancellation)) AS gross_sales,
       round(-sum(i.invoice_value) FILTER (WHERE i.is_cancellation))     AS cancelled_value,
       round(100.0 * -sum(i.invoice_value) FILTER (WHERE i.is_cancellation)
                   /  sum(i.invoice_value) FILTER (WHERE NOT i.is_cancellation), 1) AS return_rate_pct,
       count(*) FILTER (WHERE i.is_cancellation)                          AS cancellation_notes
FROM fact_invoice i
JOIN dim_customer c USING (customer_id)
WHERE i.customer_id IS NOT NULL
GROUP BY i.customer_id, c.country
HAVING sum(i.invoice_value) FILTER (WHERE NOT i.is_cancellation) > 0
ORDER BY cancelled_value DESC
LIMIT 10;

-- Match every cancellation line to the latest earlier sale of the same customer and product
CREATE OR REPLACE TABLE rpt_cancellation_lag AS
WITH sale_lines AS (
    SELECT i.customer_id, l.stock_code, i.invoice_ts AS sale_ts, l.quantity AS sale_qty
    FROM fact_invoice_line l
    JOIN fact_invoice i USING (invoice)
    WHERE NOT i.is_cancellation AND i.customer_id IS NOT NULL
),
cancel_lines AS (
    SELECT i.invoice AS cancel_invoice, l.line_no, i.customer_id, l.stock_code,
           i.invoice_ts AS cancel_ts, -l.quantity AS cancel_qty, -l.line_value AS cancel_value
    FROM fact_invoice_line l
    JOIN fact_invoice i USING (invoice)
    WHERE i.is_cancellation AND i.customer_id IS NOT NULL
),
candidates AS (
    SELECT c.*, s.sale_ts, s.sale_qty,
           row_number() OVER (PARTITION BY c.cancel_invoice, c.line_no ORDER BY s.sale_ts DESC) AS rn
    FROM cancel_lines c
    LEFT JOIN sale_lines s
           ON s.customer_id = c.customer_id
          AND s.stock_code  = c.stock_code
          AND s.sale_ts    <= c.cancel_ts
)
SELECT cancel_invoice, line_no, customer_id, stock_code, cancel_ts, cancel_qty, cancel_value,
       sale_ts, sale_qty,
       date_diff('day', sale_ts, cancel_ts) AS days_since_sale
FROM candidates
WHERE rn = 1
ORDER BY cancel_invoice, line_no;

-- How long after the sale do cancellations happen?
SELECT CASE WHEN sale_ts IS NULL          THEN '6. no earlier sale found (bought before Dec 2009)'
            WHEN days_since_sale = 0      THEN '1. same day'
            WHEN days_since_sale <= 7     THEN '2. 1-7 days'
            WHEN days_since_sale <= 30    THEN '3. 8-30 days'
            WHEN days_since_sale <= 90    THEN '4. 31-90 days'
            ELSE                               '5. over 90 days' END AS lag_band,
       count(*)                                                        AS cancellation_lines,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)              AS pct_lines,
       round(sum(cancel_value))                                        AS cancelled_value,
       round(100.0 * sum(cancel_value) / sum(sum(cancel_value)) OVER (), 1) AS pct_value
FROM rpt_cancellation_lag
GROUP BY 1
ORDER BY 1;

-- The biggest single cancellations: bulk orders cancelled within minutes
SELECT g.cancel_invoice, g.customer_id, g.stock_code, p.description, g.cancel_qty,
       round(g.cancel_value) AS cancel_value, g.sale_ts, g.cancel_ts,
       date_diff('minute', g.sale_ts, g.cancel_ts) AS minutes_after_sale
FROM rpt_cancellation_lag g
JOIN dim_product p USING (stock_code)
ORDER BY g.cancel_value DESC
LIMIT 5;

-- Share of all cancelled value that sits in the top 5 cancellation lines
SELECT round(100.0 * sum(cancel_value) FILTER (WHERE rk <= 5) / sum(cancel_value), 1) AS top5_lines_share_of_cancelled_value_pct
FROM (SELECT cancel_value, row_number() OVER (ORDER BY cancel_value DESC) AS rk FROM rpt_cancellation_lag);

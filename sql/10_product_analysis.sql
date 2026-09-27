-- =============================================================================
-- 10_product_analysis.sql : what sells, and how concentrated is the range?
-- =============================================================================
-- Product revenue is net of cancellations, so a bulk order that was cancelled
-- minutes later (see 08) does not turn its product into a "best seller".
-- =============================================================================

CREATE OR REPLACE TABLE rpt_product_sales AS
SELECT l.stock_code,
       p.description,
       sum(l.quantity) FILTER (WHERE NOT i.is_cancellation)                 AS units_sold,
       round(sum(l.line_value), 2)                                          AS net_revenue,
       count(DISTINCT i.invoice)     FILTER (WHERE NOT i.is_cancellation)   AS orders,
       count(DISTINCT i.customer_id) FILTER (WHERE NOT i.is_cancellation)   AS customers,
       round(sum(l.line_value) FILTER (WHERE NOT i.is_cancellation)
             / nullif(sum(l.quantity) FILTER (WHERE NOT i.is_cancellation), 0), 2) AS avg_unit_price,
       p.first_sold_date,
       p.last_sold_date
FROM fact_invoice_line l
JOIN fact_invoice i USING (invoice)
JOIN dim_product  p USING (stock_code)
GROUP BY l.stock_code, p.description, p.first_sold_date, p.last_sold_date
ORDER BY net_revenue DESC, l.stock_code;

-- Top 20 products by net revenue
SELECT stock_code, description, units_sold, net_revenue, orders, customers, avg_unit_price
FROM rpt_product_sales
ORDER BY net_revenue DESC
LIMIT 20;

-- Top 10 products by units
SELECT stock_code, description, units_sold, net_revenue, avg_unit_price
FROM rpt_product_sales
ORDER BY units_sold DESC
LIMIT 10;

-- Pareto: how many SKUs make up half / 80% of net revenue?
WITH ranked AS (
    SELECT stock_code, net_revenue,
           row_number() OVER (ORDER BY net_revenue DESC)      AS sku_rank,
           sum(net_revenue) OVER (ORDER BY net_revenue DESC)  AS cumulative_revenue,
           sum(net_revenue) OVER ()                           AS total_revenue
    FROM rpt_product_sales
    WHERE net_revenue > 0
)
SELECT count(*)                                                   AS skus_with_positive_revenue,
       min(sku_rank) FILTER (WHERE cumulative_revenue >= 0.5 * total_revenue) AS skus_for_50pct_revenue,
       min(sku_rank) FILTER (WHERE cumulative_revenue >= 0.8 * total_revenue) AS skus_for_80pct_revenue,
       round(100.0 * min(sku_rank) FILTER (WHERE cumulative_revenue >= 0.8 * total_revenue) / count(*), 1) AS pct_of_skus_for_80pct_revenue
FROM ranked;

-- Price band mix: cheap items dominate units, but not revenue
SELECT CASE WHEN l.unit_price < 1  THEN '1. under GBP 1'
            WHEN l.unit_price < 2  THEN '2. GBP 1-2'
            WHEN l.unit_price < 5  THEN '3. GBP 2-5'
            WHEN l.unit_price < 10 THEN '4. GBP 5-10'
            ELSE                        '5. GBP 10+' END           AS price_band,
       sum(l.quantity)                                              AS units_sold,
       round(100.0 * sum(l.quantity) / sum(sum(l.quantity)) OVER (), 1)     AS pct_units,
       round(sum(l.line_value))                                     AS gross_sales,
       round(100.0 * sum(l.line_value) / sum(sum(l.line_value)) OVER (), 1) AS pct_sales
FROM fact_invoice_line l
JOIN fact_invoice i USING (invoice)
WHERE NOT i.is_cancellation
GROUP BY 1
ORDER BY 1;

-- Basket profile of a sale invoice
SELECT count(*)                                  AS orders,
       round(avg(line_count), 1)                 AS avg_lines_per_order,
       round(quantile_cont(line_count, 0.5))     AS median_lines_per_order,
       round(avg(units), 1)                      AS avg_units_per_order,
       round(avg(invoice_value), 2)              AS avg_order_value,
       round(quantile_cont(invoice_value, 0.5), 2) AS median_order_value
FROM fact_invoice
WHERE NOT is_cancellation;

-- Products only ever sold in one of the two years (range churn)
SELECT CASE WHEN last_sold_date  < DATE '2010-12-01' THEN 'discontinued before Dec 2010'
            WHEN first_sold_date >= DATE '2010-12-01' THEN 'introduced from Dec 2010'
            ELSE 'sold in both years' END          AS product_status,
       count(*)                                    AS skus,
       round(sum(net_revenue))                     AS net_revenue
FROM rpt_product_sales
GROUP BY 1
ORDER BY 1;

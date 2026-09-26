-- =============================================================================
-- 03_schema.sql : normalise the flat file into a small star schema
-- =============================================================================
-- The source is one wide table. Splitting it into dimension and fact tables
--   * makes each analysis a JOIN rather than a filter on a 1M-row table,
--   * fixes inconsistencies once (one description per product, one country
--     per customer) instead of in every query,
--   * mirrors how a real warehouse would hold this data.
--
--   dim_customer  (customer_id)   one row per registered customer
--   dim_product   (stock_code)    one row per SKU
--   dim_country   (country)       one row per country, with a region grouping
--   fact_invoice  (invoice)       one row per invoice / cancellation note
--   fact_invoice_line             one row per line, FK to fact_invoice and dim_product
-- =============================================================================

-- dim_product: the most frequently used description wins (1,232 codes had several)
CREATE OR REPLACE TABLE dim_product AS
WITH description_counts AS (
    SELECT stock_code, description, count(*) AS n
    FROM clean_lines
    WHERE description IS NOT NULL
    GROUP BY stock_code, description
),
ranked AS (
    SELECT stock_code, description,
           row_number() OVER (PARTITION BY stock_code ORDER BY n DESC, description) AS rn
    FROM description_counts
)
SELECT r.stock_code,
       r.description,
       min(l.invoice_date) AS first_sold_date,
       max(l.invoice_date) AS last_sold_date
FROM ranked r
JOIN clean_lines l USING (stock_code)
WHERE r.rn = 1
GROUP BY r.stock_code, r.description;

-- dim_country: hand-made region grouping used by the dashboard
CREATE OR REPLACE TABLE dim_country AS
SELECT country,
       CASE
           WHEN country = 'United Kingdom' THEN 'United Kingdom'
           WHEN country IN ('EIRE', 'Germany', 'France', 'Netherlands', 'Spain', 'Switzerland', 'Belgium',
                            'Portugal', 'Channel Islands', 'Italy', 'Norway', 'Sweden', 'Cyprus', 'Finland',
                            'Austria', 'Denmark', 'Greece', 'Poland', 'Malta', 'Iceland', 'Lithuania',
                            'Czech Republic', 'European Community') THEN 'Europe (ex UK)'
           WHEN country = 'Unspecified' THEN 'Unspecified'
           ELSE 'Rest of world'
       END AS region
FROM (SELECT DISTINCT country FROM clean_lines);

-- dim_customer: one country per customer (the most frequent one; 13 customers had two)
CREATE OR REPLACE TABLE dim_customer AS
WITH country_counts AS (
    SELECT customer_id, country, count(*) AS n
    FROM clean_lines
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id, country
),
ranked AS (
    SELECT customer_id, country,
           row_number() OVER (PARTITION BY customer_id ORDER BY n DESC, country) AS rn
    FROM country_counts
),
first_purchase AS (
    SELECT customer_id,
           min(invoice_date)  AS first_purchase_date,
           min(invoice_month) AS cohort_month
    FROM clean_lines
    WHERE customer_id IS NOT NULL AND NOT is_cancellation
    GROUP BY customer_id
)
SELECT r.customer_id,
       r.country,
       f.first_purchase_date,
       f.cohort_month
FROM ranked r
LEFT JOIN first_purchase f USING (customer_id)
WHERE r.rn = 1;

-- fact_invoice: header level. Value is the sum of its lines (negative for cancellations)
CREATE OR REPLACE TABLE fact_invoice AS
SELECT invoice,
       any_value(customer_id)                  AS customer_id,
       any_value(country)                      AS country,
       min(invoice_ts)                         AS invoice_ts,
       min(invoice_date)                       AS invoice_date,
       min(invoice_month)                      AS invoice_month,
       any_value(is_cancellation)              AS is_cancellation,
       count(*)                                AS line_count,
       sum(quantity)                           AS units,
       CAST(sum(line_value) AS DECIMAL(14,2))  AS invoice_value
FROM clean_lines
GROUP BY invoice;

-- fact_invoice_line: the grain of the source, minus the columns that belong to the header
CREATE OR REPLACE TABLE fact_invoice_line AS
SELECT invoice,
       row_number() OVER (PARTITION BY invoice ORDER BY stock_code) AS line_no,
       stock_code,
       quantity,
       unit_price,
       line_value
FROM clean_lines;

-- Row counts per table
SELECT 'dim_customer' AS table_name, count(*) AS row_count FROM dim_customer
UNION ALL SELECT 'dim_product',       count(*) FROM dim_product
UNION ALL SELECT 'dim_country',       count(*) FROM dim_country
UNION ALL SELECT 'fact_invoice',      count(*) FROM fact_invoice
UNION ALL SELECT 'fact_invoice_line', count(*) FROM fact_invoice_line;

-- Referential integrity checks (all should be zero)
SELECT
    (SELECT count(*) FROM fact_invoice_line l LEFT JOIN fact_invoice i USING (invoice) WHERE i.invoice IS NULL)               AS lines_without_invoice,
    (SELECT count(*) FROM fact_invoice_line l LEFT JOIN dim_product p USING (stock_code) WHERE p.stock_code IS NULL)          AS lines_without_product,
    (SELECT count(*) FROM fact_invoice i LEFT JOIN dim_customer c USING (customer_id) WHERE i.customer_id IS NOT NULL AND c.customer_id IS NULL) AS invoices_without_customer,
    (SELECT count(*) FROM fact_invoice i LEFT JOIN dim_country c USING (country) WHERE c.country IS NULL)                     AS invoices_without_country,
    (SELECT count(*) FROM (SELECT invoice FROM fact_invoice GROUP BY invoice HAVING count(*) > 1))                            AS duplicate_invoice_keys;

-- Invoices whose lines disagree on customer, country or timestamp (should be zero)
SELECT count(*) AS invoices_with_mixed_headers
FROM (
    SELECT invoice
    FROM clean_lines
    GROUP BY invoice
    HAVING count(DISTINCT customer_id) > 1 OR count(DISTINCT country) > 1 OR count(DISTINCT invoice_ts) > 1
);

-- Region summary, joining the tables the way later scripts do
SELECT c.region,
       count(DISTINCT i.invoice)                    AS invoices,
       count(DISTINCT i.customer_id)                AS customers,
       round(sum(l.line_value))                     AS net_revenue_gbp
FROM fact_invoice_line l
JOIN fact_invoice i USING (invoice)
JOIN dim_country  c USING (country)
GROUP BY c.region
ORDER BY net_revenue_gbp DESC;

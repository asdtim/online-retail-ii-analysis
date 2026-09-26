-- =============================================================================
-- 01_data_profiling.sql : what is actually in the raw data
-- =============================================================================
-- Every cleaning rule in 02_clean.sql is justified by a query in this file.
-- Run:  python scripts/run_sql.py sql/01_data_profiling.sql
-- =============================================================================

-- 1. Size of the data set and coverage
SELECT count(*)                         AS row_count,
       count(DISTINCT invoice)          AS invoices,
       count(DISTINCT customer_id)      AS customers,
       count(DISTINCT stock_code)       AS stock_codes,
       count(DISTINCT country)          AS countries,
       min(invoice_ts)::DATE            AS first_day,
       max(invoice_ts)::DATE            AS last_day
FROM raw_transactions;

-- 2. The two Excel sheets overlap: 1-9 Dec 2010 is present in BOTH sheets
SELECT source_sheet,
       count(*)                 AS rows_total,
       min(invoice_ts)::DATE    AS first_day,
       max(invoice_ts)::DATE    AS last_day,
       count(*) FILTER (WHERE invoice_ts >= '2010-12-01' AND invoice_ts < '2010-12-10') AS rows_1_to_9_dec_2010
FROM raw_transactions
GROUP BY source_sheet
ORDER BY source_sheet;

-- 2b. Proof that the overlap is a pure duplicate: every row in that window has an identical twin in the other sheet
WITH window_rows AS (
    SELECT invoice, stock_code, description, quantity, invoice_ts, unit_price, customer_id, country,
           count(DISTINCT source_sheet) AS sheets_seen,
           count(*)                     AS copies
    FROM raw_transactions
    WHERE invoice_ts >= '2010-12-01' AND invoice_ts < '2010-12-10'
    GROUP BY ALL
)
SELECT count(*)                                        AS distinct_rows_in_window,
       count(*) FILTER (WHERE sheets_seen = 2)         AS rows_in_both_sheets,
       count(*) FILTER (WHERE sheets_seen = 1)         AS rows_in_one_sheet_only
FROM window_rows;

-- 3. Missing values: about a quarter of lines have no customer id (guest checkouts)
SELECT count(*)                                                    AS row_count,
       count(*) - count(customer_id)                               AS rows_without_customer,
       round(100.0 * (count(*) - count(customer_id)) / count(*), 1) AS pct_without_customer,
       count(*) - count(description)                               AS rows_without_description
FROM raw_transactions;

-- 4. Invoice number patterns: plain digits = sale, 'C' prefix = cancellation, 'A' prefix = accounting adjustment
SELECT CASE WHEN regexp_matches(invoice, '^[0-9]+$') THEN 'numeric (sale)'
            ELSE left(invoice, 1) || '-prefixed' END       AS invoice_type,
       count(*)                                           AS rows_total,
       count(DISTINCT invoice)                            AS invoices,
       round(sum(quantity * unit_price), 0)               AS line_value_gbp
FROM raw_transactions
GROUP BY 1
ORDER BY rows_total DESC;

-- 5. Sign of quantity and price, split by cancellation flag
SELECT invoice LIKE 'C%'                                                        AS is_cancellation,
       CASE WHEN quantity > 0 THEN '+' WHEN quantity = 0 THEN '0' ELSE '-' END  AS quantity_sign,
       CASE WHEN unit_price > 0 THEN '+' WHEN unit_price = 0 THEN '0' ELSE '-' END AS price_sign,
       count(*)                                                                 AS rows_total,
       round(sum(quantity * unit_price), 0)                                     AS line_value_gbp
FROM raw_transactions
GROUP BY ALL
ORDER BY ALL;

-- 6. Non-product stock codes (real products are 5 digits + optional letter suffix)
SELECT stock_code,
       min(description)                     AS example_description,
       count(*)                             AS rows_total,
       round(sum(quantity * unit_price), 0) AS line_value_gbp
FROM raw_transactions
WHERE NOT regexp_matches(stock_code, '^[0-9]{5}[A-Za-z]*$')
GROUP BY stock_code
ORDER BY rows_total DESC;

-- 7. Negative quantities that are NOT cancellations: stock write-offs, damages, 'check' rows
SELECT description,
       count(*)      AS rows_total,
       sum(quantity) AS units
FROM raw_transactions
WHERE quantity < 0 AND invoice NOT LIKE 'C%'
GROUP BY description
ORDER BY rows_total DESC
LIMIT 15;

-- 8. Zero-price lines: what are they?
SELECT description,
       count(*)      AS rows_total,
       sum(quantity) AS units
FROM raw_transactions
WHERE unit_price = 0
GROUP BY description
ORDER BY rows_total DESC
LIMIT 15;

-- 9. Exact duplicate lines within the same sheet (not explained by the overlap)
SELECT count(*)            AS duplicated_line_groups,
       sum(copies - 1)     AS extra_rows_to_drop,
       round(sum((copies - 1) * quantity * unit_price), 0) AS extra_value_gbp
FROM (
    SELECT invoice, stock_code, description, quantity, invoice_ts, unit_price, customer_id, country, source_sheet,
           count(*) AS copies
    FROM raw_transactions
    GROUP BY ALL
    HAVING count(*) > 1
);

-- 10. One stock code, several descriptions (typos, renamed products)
SELECT count(*) AS stock_codes_with_multiple_descriptions
FROM (
    SELECT stock_code
    FROM raw_transactions
    WHERE description IS NOT NULL
    GROUP BY stock_code
    HAVING count(DISTINCT description) > 1
);

-- 11. Customers recorded under more than one country
SELECT count(*) AS customers_with_multiple_countries
FROM (
    SELECT customer_id
    FROM raw_transactions
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id
    HAVING count(DISTINCT country) > 1
);

-- 12. Countries by number of lines
SELECT country, count(*) AS rows_total, count(DISTINCT customer_id) AS customers
FROM raw_transactions
GROUP BY country
ORDER BY rows_total DESC;

-- 13. Extreme quantities (typos and bulk orders that get cancelled straight away)
SELECT invoice, stock_code, description, quantity, unit_price, customer_id, invoice_ts
FROM raw_transactions
ORDER BY abs(quantity) DESC
LIMIT 10;

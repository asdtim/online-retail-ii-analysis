-- =============================================================================
-- 02_clean.sql : cleaning rules
-- =============================================================================
-- Each rule below is numbered and matches a finding in 01_data_profiling.sql.
-- Cancellations are KEPT and flagged, because the returns analysis needs them;
-- every revenue figure later in the project is net of cancellations.
--
--   Rule 1  Drop the duplicated 9-day window (1-9 Dec 2010) that both Excel
--           sheets contain. 22,523 rows.
--   Rule 2  Drop exact duplicate lines within a sheet (same invoice, product,
--           quantity, price, timestamp, customer). 12,133 rows, GBP 55k.
--   Rule 3  Drop non-merchandise codes: postage, carriage, manual adjustments,
--           bank charges, Amazon fees, samples, bad-debt write-offs, test rows,
--           gift vouchers. They are not product sales.
--   Rule 4  Drop lines with unit price <= 0. This removes free/zero-priced
--           lines, and every stock write-off ("damages", "check", "?") because
--           all of those carry a zero price.
--   Rule 5  A sale line must have quantity > 0; a cancellation line must have
--           quantity < 0 (one cancellation row violates this and is dropped).
-- =============================================================================

CREATE OR REPLACE TABLE clean_lines AS
WITH deduplicated AS (
    -- Rules 1 and 2. DISTINCT collapses identical rows; the overlap is removed
    -- by ignoring the second sheet's copy of 1-9 Dec 2010.
    SELECT DISTINCT
        invoice,
        trim(stock_code)   AS stock_code,
        trim(description)  AS description,
        quantity,
        invoice_ts,
        unit_price,
        customer_id,
        country
    FROM raw_transactions
    WHERE NOT (source_sheet = 'Year 2010-2011' AND invoice_ts < TIMESTAMP '2010-12-10')
),
typed AS (
    SELECT
        *,
        invoice LIKE 'C%' AS is_cancellation
    FROM deduplicated
)
SELECT
    invoice,
    stock_code,
    description,
    quantity,
    unit_price,
    CAST(quantity * unit_price AS DECIMAL(14,2)) AS line_value,     -- negative on cancellations
    invoice_ts,
    CAST(invoice_ts AS DATE)                       AS invoice_date,
    CAST(date_trunc('month', invoice_ts) AS DATE)  AS invoice_month,
    customer_id,
    country,
    is_cancellation
FROM typed
WHERE
    -- Rule 3: merchandise only
    stock_code NOT IN ('POST', 'DOT', 'C2', 'C3', 'D', 'M', 'm', 'S', 'B', 'BANK CHARGES',
                       'ADJUST', 'ADJUST2', 'AMAZONFEE', 'PADS', 'CRUK', 'TEST001', 'TEST002', 'GIFT')
    AND stock_code NOT LIKE 'gift_%'
    -- Rule 4: priced lines only
    AND unit_price > 0
    -- Rule 5: sign must agree with the line type
    AND ((NOT is_cancellation AND quantity > 0) OR (is_cancellation AND quantity < 0));

-- Reconciliation: rows and value remaining after each rule
WITH raw AS (
    SELECT count(*) AS rows_total, round(sum(quantity * unit_price)) AS value_gbp FROM raw_transactions
),
after_overlap AS (
    SELECT count(*) AS rows_total, round(sum(quantity * unit_price)) AS value_gbp FROM raw_transactions
    WHERE NOT (source_sheet = 'Year 2010-2011' AND invoice_ts < TIMESTAMP '2010-12-10')
),
after_dedupe AS (
    SELECT count(*) AS rows_total, round(sum(quantity * unit_price)) AS value_gbp FROM (
        SELECT DISTINCT invoice, stock_code, description, quantity, invoice_ts, unit_price, customer_id, country
        FROM raw_transactions
        WHERE NOT (source_sheet = 'Year 2010-2011' AND invoice_ts < TIMESTAMP '2010-12-10'))
),
final AS (
    SELECT count(*) AS rows_total, round(sum(line_value)) AS value_gbp FROM clean_lines
)
SELECT 'raw rows'                                    AS step, rows_total, value_gbp FROM raw
UNION ALL SELECT '1. after removing sheet overlap',    rows_total, value_gbp FROM after_overlap
UNION ALL SELECT '2. after removing duplicate lines',  rows_total, value_gbp FROM after_dedupe
UNION ALL SELECT '3-5. after code/price/sign rules',   rows_total, value_gbp FROM final;

-- What is left: sales vs cancellations
SELECT is_cancellation,
       count(*)                     AS rows_total,
       count(DISTINCT invoice)      AS invoices,
       count(DISTINCT customer_id)  AS customers,
       sum(quantity)                AS units,
       round(sum(line_value))       AS value_gbp
FROM clean_lines
GROUP BY is_cancellation
ORDER BY is_cancellation;

-- Share of sales value that cannot be attributed to a customer (guest checkouts)
SELECT round(100.0 * sum(line_value) FILTER (WHERE customer_id IS NULL) / sum(line_value), 1) AS pct_value_without_customer,
       round(100.0 * count(*) FILTER (WHERE customer_id IS NULL) / count(*), 1)              AS pct_rows_without_customer
FROM clean_lines
WHERE NOT is_cancellation;

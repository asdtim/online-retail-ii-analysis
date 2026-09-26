-- =============================================================================
-- 00_load_raw.sql : load the source CSV into DuckDB, untouched
-- =============================================================================
-- Source: UCI Machine Learning Repository, "Online Retail II" (CC BY 4.0)
--         https://archive.ics.uci.edu/dataset/502/online+retail+ii
-- The CSV is produced by scripts/01_excel_to_csv.py from the two Excel sheets.
--
-- Nothing is cleaned here on purpose. Keeping an untouched copy means every
-- decision in 02_clean.sql can be checked against the original numbers.
-- =============================================================================

-- Raw table: one row per invoice line, exactly as delivered
CREATE OR REPLACE TABLE raw_transactions AS
SELECT
    Invoice                      AS invoice,        -- 6-digit number; 'C' prefix = cancellation
    StockCode                    AS stock_code,     -- 5-digit product code (+ optional letter suffix)
    Description                  AS description,
    Quantity                     AS quantity,       -- negative on cancellations / stock adjustments
    InvoiceDate                  AS invoice_ts,
    Price                        AS unit_price,     -- GBP, excluding VAT
    CAST(CustomerID AS INTEGER)  AS customer_id,    -- NULL for guest / unregistered checkouts
    Country                      AS country,
    source_sheet
FROM read_csv('data/raw/online_retail_II.csv',
              header = true,
              types  = {'Invoice': 'VARCHAR', 'StockCode': 'VARCHAR', 'Description': 'VARCHAR',
                        'Quantity': 'INTEGER', 'InvoiceDate': 'TIMESTAMP', 'Price': 'DECIMAL(12,4)',
                        'CustomerID': 'DOUBLE', 'Country': 'VARCHAR', 'source_sheet': 'VARCHAR'});

-- Sanity check: expect 1,067,371 rows, 2009-12-01 to 2011-12-09
SELECT count(*) AS row_count,
       min(invoice_ts) AS first_ts,
       max(invoice_ts) AS last_ts
FROM raw_transactions;

-- =============================================================================
-- 99_export_tableau.sql : write the report tables to CSV for Tableau Public
-- =============================================================================
-- Every file lands in outputs/tableau/. The small aggregated files are
-- committed to the repository; the line-level extract (~90 MB) is not.
-- =============================================================================

COPY rpt_monthly_sales            TO 'outputs/tableau/monthly_sales.csv'            (HEADER, DELIMITER ',');
COPY rpt_monthly_sales_by_region  TO 'outputs/tableau/monthly_sales_by_region.csv'  (HEADER, DELIMITER ',');
COPY rpt_orders_by_weekday_hour   TO 'outputs/tableau/orders_by_weekday_hour.csv'   (HEADER, DELIMITER ',');
COPY rpt_cohort_retention         TO 'outputs/tableau/cohort_retention.csv'         (HEADER, DELIMITER ',');
COPY rpt_retention_curve          TO 'outputs/tableau/retention_curve.csv'          (HEADER, DELIMITER ',');
COPY rpt_rfm_customer             TO 'outputs/tableau/rfm_customers.csv'            (HEADER, DELIMITER ',');
COPY rpt_rfm_segment              TO 'outputs/tableau/rfm_segments.csv'             (HEADER, DELIMITER ',');
COPY rpt_orders_per_customer      TO 'outputs/tableau/orders_per_customer.csv'      (HEADER, DELIMITER ',');
COPY rpt_repeat_by_cohort         TO 'outputs/tableau/repeat_by_cohort.csv'         (HEADER, DELIMITER ',');
COPY rpt_returns_by_product       TO 'outputs/tableau/returns_by_product.csv'       (HEADER, DELIMITER ',');
COPY rpt_country                  TO 'outputs/tableau/country_sales.csv'            (HEADER, DELIMITER ',');
COPY rpt_country_growth           TO 'outputs/tableau/country_growth.csv'           (HEADER, DELIMITER ',');
COPY rpt_product_sales            TO 'outputs/tableau/product_sales.csv'            (HEADER, DELIMITER ',');

-- Line-level extract with the dimensions joined in, for ad-hoc exploration in Tableau (not committed)
COPY (
    SELECT l.invoice,
           i.invoice_date,
           i.invoice_month,
           i.is_cancellation,
           i.customer_id,
           i.country,
           c.region,
           l.stock_code,
           p.description,
           l.quantity,
           l.unit_price,
           l.line_value
    FROM fact_invoice_line l
    JOIN fact_invoice i USING (invoice)
    JOIN dim_country  c USING (country)
    JOIN dim_product  p USING (stock_code)
) TO 'outputs/tableau/sales_lines.csv' (HEADER, DELIMITER ',');

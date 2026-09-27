# Dashboard notes

The Tableau Public workbook has four views. Each one reads a CSV that
`sql/99_export_tableau.sql` writes to `outputs/tableau/`.

| View | File | Fields used |
|---|---|---|
| Monthly net revenue | `monthly_sales.csv` | invoice_month, net_revenue, is_complete_month |
| Cohort retention heat map | `cohort_retention.csv` | cohort_label, period_number, retention_pct, cohort_customers |
| RFM segments | `rfm_segments.csv` | segment, pct_customers, pct_revenue, net_revenue |
| Revenue by country | `country_sales.csv` | country, region, net_revenue, customers, avg_order_value |

Things worth knowing if you rebuild it:

- `period_number` has to be treated as a dimension (discrete) in Tableau, not
  a measure, or the heat map collapses into one column.
- Cap the heat map colour range at about 50%. Month 0 is always 100% and
  washes out everything else otherwise.
- Tableau does not recognise "EIRE", "RSA" or "Channel Islands" as places.
  Map them by hand to Ireland, South Africa and Jersey; leave "European
  Community" and "Unspecified" blank.
- The line-level extract `sales_lines.csv` (about 120 MB, not committed) is
  only there for ad-hoc filtering. The dashboard does not need it.

Link: to be added once published.

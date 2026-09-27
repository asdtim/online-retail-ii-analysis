# Dashboard notes

Published workbook: https://public.tableau.com/app/profile/tim.smitn/viz/online_retail_dashboard_17905382659160/OnlineRetailII

The dashboard has six views. Each one reads a CSV that
`sql/99_export_tableau.sql` writes to `outputs/tableau/`.

| View | File | Fields used |
|---|---|---|
| Monthly net revenue | `monthly_sales.csv` | invoice_month, net_revenue, is_complete_month |
| Overseas markets map | `country_sales.csv` | country, region, net_revenue, customers, avg_order_value |
| Cohort retention heat map | `cohort_retention.csv` | cohort_label, period_number, retention_pct, cohort_customers |
| RFM segments | `rfm_segments.csv` | segment, pct_customers, pct_revenue, net_revenue |
| Orders by weekday and hour | `orders_by_weekday_hour.csv` | weekday, weekday_num, hour_of_day, orders |
| Overseas markets year on year (slope chart) | `country_growth.csv` | country, revenue_dec09_nov10, revenue_dec10_nov11, growth_pct |

Things worth knowing if you rebuild it:

- `period_number` and `hour_of_day` have to be treated as dimensions (discrete)
  in Tableau, not measures, or the heat maps collapse into one column.
- The cohort heat map shows months 1-12 and leaves out the Dec 2009 group,
  which is not a real cohort because the data starts that month.
- The trend line uses complete months only; Dec 2011 has nine days of data.
- The map leaves out the United Kingdom (85% of revenue) so the other markets
  are visible, and renames EIRE, RSA, Channel Islands and Korea to names the
  geocoder recognises (Ireland, South Africa, Jersey, South Korea).
- The RFM colour groups are Active (Champions, Loyal Customers, Potential
  Loyalists, New Customers, Promising), At risk (At Risk, Cannot Lose Them,
  Need Attention, About to Sleep) and Lapsed (Hibernating, Lost).
- The slope chart compares the two complete twelve-month windows (Dec 2009 -
  Nov 2010 and Dec 2010 - Nov 2011) for the six largest overseas markets.
- The line-level extract `sales_lines.csv` (about 120 MB, not committed) is
  only there for ad-hoc filtering. The dashboard does not need it.

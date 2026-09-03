# Date dimension

`documents/dates_import.csv` contains a continuous daily calendar from
2007-05-01 through 2050-12-31. Its financial-quarter boundaries are supplied as
`financial_quarter_start` and `financial_quarter_end`, and the loader validates
that every date falls between them.

## Objects

- `dbo.dates` stores static calendar and financial-period attributes.
- `dbo.date_catalogue` exposes dynamic reporting flags. Placeholder dates remain
  in `dbo.dates` for referential integrity but are excluded from the view.

The relative flags are view expressions rather than stored columns because
their values change at midnight. They are evaluated using the SQL Server local
date from `SYSDATETIME()`:

- `is_today`, `is_yesterday`, `is_current_week`
- `is_current_month`
- `is_current_financial_month`, `is_current_financial_quarter`,
  `is_current_financial_year`, `is_previous_financial_year`
- `is_financial_month_to_date`, `is_financial_quarter_to_date`,
  `is_financial_year_to_date`
- `is_last_financial_month`, `is_last_financial_quarter`,
  `is_last_financial_year`
- `is_rolling_12_financial_months`

“Rolling 12 financial months” means the complete current financial month plus
the preceding eleven financial months. Financial periods use the boundaries in
the CSV rather than assuming calendar-month or fixed May-to-April boundaries.

The importer also adds placeholder keys for 1900-01-01 and 1901-01-01. Current
preorder data uses 1900-01-01 as an unknown order date, while `date_key_ny`
projects it to 1901-01-01. The placeholder rows allow all date-key foreign keys
to remain checked without pretending those dates have valid financial-period
attributes.

## Deployment order

1. Deploy `sql/functions/fnc_date_key.sql`.
2. Deploy `sql/tables/dates.sql`.
3. Deploy `sql/procedures/update_dates_table.sql`.
4. Load the CSV with `python scripts/run_update.py dates`.
5. Deploy `sql/views/date_catalogue.sql`.
6. Deploy `sql/constraints/date_foreign_keys.sql`.

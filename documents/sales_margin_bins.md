# Sales margin bin for the C# app

Query `data_control.dbo.sales_margin_bins`. Each result row is one stored sales
line. There is one persisted `dbo.sales.margin_bin` column, immediately after
`quantity`. The view exposes `quantity`, `margin_bin`, `margin_bin_label`,
then the currency amounts. The three former currency-bin columns are removed.

The bin uses adjusted margin / sales in the entity's currency:

| Entity | Amounts used |
| --- | --- |
| Shiner Ltd | GBP adjusted margin / GBP sales |
| Shiner B.V | EUR adjusted margin / EUR sales |
| Shiner LLC | USD adjusted margin / USD sales |

Changing the displayed reporting currency does not change the sale's bin.
All GBP/EUR/USD sales and adjusted-margin amounts remain available to aggregate.

The bin is SQL `smallint` (C# `short`) and is also the sort key.
The view label is `varchar(32)`.

| Bin | Meaning |
| --- | --- |
| -10 | <= -100% |
| -9 through 10 | Upper-inclusive ten-percentage-point bands; e.g. 3 is > 20% & <= 30% |
| 11 | > 100% |
| 127 | Undefined margin: zero sales in the entity currency or an unmapped entity |

Negative sales retain the adjusted-margin/sales ratio's sign. The expressions
compare amounts to boundaries instead of rounding the ratio to one decimal
place; SQL decimal arithmetic applies. Zero margin with nonzero sales is in
> -10% & <= 0%. Add an explicit currency mapping when onboarding a new entity.

The view retains the original report's intercompany/exclusion filters and
Blue Tomato customer/brand exclusions. It does not fix a start date; supply
the date range from the app.

```sql
-- Bind @entity as nvarchar(20), @from_date and @to_date as date.
-- @to_date is exclusive.
SELECT margin_bin,
       margin_bin_label,
       COUNT_BIG(*) AS sales_line_count,
       SUM(gbp_sales) AS sales,
       SUM(gbp_adjusted_margin) AS adjusted_margin,
       SUM(gbp_adjusted_margin) / NULLIF(SUM(gbp_sales), 0) AS adjusted_margin_pct
FROM dbo.sales_margin_bins
WHERE entity = @entity
  AND posting_date >= @from_date
  AND posting_date < @to_date
GROUP BY margin_bin, margin_bin_label
ORDER BY margin_bin;
```

Use EUR/USD amount columns when those reporting currencies are required;
keep the same bin columns. The percentage is a fraction (0.30 means 30%).
Calculate overall margin as total adjusted margin / total sales, not an
average of row percentages. An item can appear in multiple bins.

## Updates and index

`update_sales_table` inserts with explicit column names and omits computed
columns. Keep `margin_bin` out of the insert list and staging data. SQL Server
automatically maintains it when the entity, relevant sales or adjusted margin
changes, including updates by `update_adjusted_margin`.

`IX_sales_entity_posting_date` retains its entity/date keys and existing
amount/filter columns. Its INCLUDE list contains one `margin_bin`, replacing
the three old bins. This covers the example query without adding another
index. Reassess indexing if the app's dominant filters change.

As with the existing computed-column and filtered indexes, use ANSI_NULLS,
ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL and
QUOTED_IDENTIFIER ON, and NUMERIC_ROUNDABORT OFF on writing connections.
Use those settings on reading connections so the optimizer can use the
indexes. See [Microsoft's computed index requirements](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/indexes-on-computed-columns).

## Deployment and verification

For a database with the three legacy bins, run
`sql/migrations/20260924_consolidate_sales_margin_bin.sql` through
`tools/db-query.ps1` with a sufficient timeout. It rebuilds the table in a
transaction to put the bin directly after quantity. It holds writes until
commit, checks every original sales value and row count, and verifies each
new bin equals the previous bin for the entity's currency. It also checks
column metadata, indexes and foreign keys. An error rolls everything back.

The earlier `20260924_add_sales_margin_bins.sql` and
`20260924_widen_sales_doc_type.sql` files describe the preceding migrations.
For a fresh empty database, `sql/tables/sales.sql` and
`sql/views/sales_margin_bins.sql` define the final single-bin schema.
Do not run the table fresh-create script on populated data: it drops the table.
`doc_type` remains `nvarchar(5)`.

`tools/test-sales-margin-bins.ps1` tests 156 boundary cases for each of the
three entities using local fixtures. It also checks differing currency
amounts, entity-only updates, unrelated currency changes, unknown entities,
inserts, margin/sales updates, index maintenance and deletes.

`sql/analysis/validate_sales_margin_bins.sql` checks the deployed table with
a single copied row inside a rolled-back transaction, including five-character
document types and currency selection after entity changes. It then checks the
column position and compares an app aggregation with the source totals.
It does not invoke the full sales ingestion job.

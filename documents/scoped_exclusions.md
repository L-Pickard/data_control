# Global and PST exclusions

On 19 October 2026, `data_control.dbo.exclusions` was extended in place. The 125 original rules and their customer/vendor flag results were compared before and after and were unchanged. Report 1, **Shiner Combined PST**, has 76 independent rules: 23 for `sales`, 23 for `sales_orders`, and 30 for `purchase_orders`. Company mappings are exactly those supplied by the user.

| Field | Meaning |
|---|---|
| `exclusion_rule_id` | Identity primary key for an individual rule |
| `rule_scope` | `global` for existing rules; `pst` for report-specific rules |
| `pst_id` | Foreign key to `portal.pst_reports`; NULL for global rules |
| `target_table` | Where a PST rule applies; empty string for global rules |
| `table_name` | Where the code belongs: `customers` or `vendors` |
| `id` | Customer or vendor code |
| `entity`, `type`, `brand_id` | Existing meanings, unchanged |

The unique index includes scope, report, target table and the original five-column key. Legacy inserts that name those five columns default to global rules. PST rules are whole-party exclusions: customer rules for sales/sales orders, vendor rules for purchase orders. There is no wildcard company or automatic reversal of the supplied company mapping.

## Applying a report set

PST rules do not change `sales.exclusion` or the global computed order flags. A PST query must explicitly apply its report ID and target table. Use parameterised, set-based predicates, for example:

```sql
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.exclusions AS ex
    WHERE ex.rule_scope = N'pst'
        AND ex.pst_id = @pst_id
        AND ex.target_table = N'sales'
        AND ex.entity = sl.entity
        AND ex.id = sl.customer_id
)
```

For sales orders, match `sell_to_customer_id` and target `sales_orders`. For purchase orders, match `vendor_id` and target `purchase_orders`. `dbo.fnc_is_pst_exclusion` also provides a single-party lookup; prefer `NOT EXISTS` for report fact queries.

To add another set, insert a distinct ID and description into `portal.pst_reports`, then insert `rule_scope=N'pst'`, that ID, the target table and the party/company keys into `dbo.exclusions`. Store the description only in the report catalogue. `last_updated` is UTC, defaults on catalogue creation, and should be updated by the process that refreshes that report; it is not an automatic timestamp for every rule edit.

The catalogue's old, unused exclusion columns were retained as nullable columns. No existing catalogue rows were present. Fresh installations create `sql/tables/portal/pst_reports.sql` before exclusions. The consolidation migration removes the superseded dbo catalogue and portal settings tables.

## Existing app and snapshots

The Exclusions & Deductions app continues to manage **global** rules. Its read and snapshot-comparison SQL explicitly filters scope; the existing add/delete procedures and all four global flag functions also filter scope. Global snapshot saves/restores cover global rules and deductions only and preserve PST rules. Old snapshots remain usable. PST rule editing and PST snapshots are not added to the portal in this change.

The potential-sell-through update procedure is still a placeholder; populating this configuration does not implement the PST report calculation. Existing dashboard Preorders SQL has not been changed to apply a PST set.

## Deployment and rollback

Database source and one-time scripts are in the adjacent **data_control** repository:

- `sql/migrations/20261019_scoped_exclusions.sql`: applied to shinersql18/data_control.
- `sql/migrations/20261019_scoped_exclusions_rollback.sql`: guarded rollback; refuses if report rules/catalogue have changed. Removes the original 76 PST rules and catalogue row, restores previous functions/procedures and the old exclusions key/schema, preserving current global rules.
- `sql/diagnostics/check_scoped_exclusions.sql`: run inside an outer transaction and roll back afterwards. Exercises report/table/company boundaries, global flags, add/delete collisions and global snapshot restore.

Run migration scripts on one connection with errors stopping execution. The migration and rollback were both rehearsed inside transactions. Four non-persisted computed flag columns on sales/purchase orders must be recreated with their exact expressions to permit ALTER FUNCTION. Their ordinal positions move to the end of those tables; consumers must use named columns. Stored order data is preserved.

The dashboard SQL changes need the usual portal publish/deployment; no IIS deployment was performed. For rollback, coordinate reverting the dashboard to checkpoint `59e8975` with the database rollback, because the newer dashboard queries require `rule_scope`. Warehouse checkpoint before the change is `86424c9`. Git commits alone do not roll back live database changes.

Ignored diagnostic backups and before/after comparisons are under dashboard_app's `artifacts/exclusion-migration`. All 380 application tests, 81 preview smoke checks and the transactional SQL checks passed. The embedded app list and snapshot comparison SQL each returned only the 125 global exclusions.

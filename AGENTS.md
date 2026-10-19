# Codex Workspace Notes

## SQL Server Access

Use `tools/db-query.ps1` for ad hoc SQL queries instead of embedding credentials in commands.

The script reads the password from `CODEX_SQL_PASSWORD`, first from the process/user environment and then from `.codex-sql.env`. Do not print, copy, or commit the password.

The sandbox may block direct TCP sockets. If the helper fails with a socket permission error, rerun it with escalated permissions rather than falling back to putting credentials on a command line.

Current helper usage:

```powershell
.\tools\db-query.ps1 -Query "SELECT @@SERVERNAME AS server_name, DB_NAME() AS database_name;"
```

For SQL files:

```powershell
.\tools\db-query.ps1 -InputFile .\sql\functions\fnc_calculate_item_royalty.sql
```

The helper is configured for `shinersql18.data_control`:

```powershell
$builder['Data Source'] = 'tcp:shinersql18'
$builder['Initial Catalog'] = 'data_control'
$builder['User ID'] = 'codex_assistant'
```

For complex SQL, prefer `-InputFile` so quoting and embedded strings are handled by SQL Server rather than by PowerShell command-line parsing.

## Permission Model

The intended SQL login is `codex_assistant`.

Expected access:

- `data_control`: create/alter/drop objects, read/write data, execute procedures/functions, view definitions.
- Source databases such as `NAV_LIVE` and `Finance`: read-only access and view definitions.
- Do not grant broad server-level roles such as `sysadmin`.

## Finance Production Protection

Treat every object and integration in the `Finance` database on `shinersql18`
as production-critical.

- Never create, alter, drop, execute for mutation, or otherwise modify any
  `shinersql18.Finance` object, data, stored procedure, function, job,
  integration, or production code unless the user expressly authorizes that
  exact Finance change in the current request.
- Permission to change `data_control`, inspect Finance, fix an adjacent system,
  or perform a broadly described deployment is not permission to change
  Finance production.
- Before an authorized Finance change, state the exact database objects and
  expected production impact, then wait for explicit confirmation if those
  details were not already authorized by the user.
- Keep `codex_assistant` read-only in Finance by default. Do not request or grant
  Finance DDL/DML, bulk-operation, or server-level permissions proactively.
- Read-only diagnosis and definition inspection are allowed. If diagnosis shows
  that a Finance mutation is required, stop and request explicit authorization
  before making it.
- Code found in the `Finance-db` repository is not automatically authorized for
  deployment to Finance production.

## Safety

- Prefer read-only queries unless the user explicitly asks for changes.
- For DDL/DML against `data_control`, explain the intended change before running it.
- Never run destructive SQL such as `DROP`, `TRUNCATE`, or broad `DELETE` unless the user explicitly requests it or the SQL file being deployed is already understood to recreate that object.
- When using `sqlcmd`, prefer `-b` so failures stop the command and are visible.

## Portal schema

- `[portal]` holds the Shiner web portal's own data (people by Windows SID, app-managed groups, report grants, audit). It was created on 25 September 2026; the schema is `sql/database/schema_portal.sql` and the table files are `sql/tables/portal/*.sql` and never drop (they hold access rights).
- Schema ownership changes and GRANTs need a `db_owner` Windows login; the `codex_assistant` helper (db_ddladmin) cannot do them. Ask the user to run such scripts with `sqlcmd -S tcp:shinersql18 -d data_control -E -N -C -b -i <file>`.
- `shiner_reports` is the portal's runtime SQL login: SELECT on the warehouse objects it reads, SELECT/INSERT/UPDATE/DELETE on `[portal]` (`sql/database/grants_shiner_reports_portal.sql`). Its password is never stored in this repo; reset it with `tools/reset-shiner-reports-password.ps1`.
- `[portal].[report_bookmarks]` (schema version 2, `sql/tables/portal/report_bookmarks.sql`) holds each person's saved report views; the portal validates filter_json before saving. Record each portal schema change in `[portal].[schema_versions]`.
- `[portal].[user_preferences]` and `[portal].[settings]` (schema version 3, `sql/tables/portal/user_preferences.sql` and `settings.sql`) hold each person's own portal settings and profile picture, and the workspace settings an administrator chooses (the default theme). No new grant is needed (`shiner_reports` has DML on SCHEMA::portal).


## Item thumbnails

- `scripts/make_item_thumbnails.py` (logic in `shinerutils/updates/item_thumbnails.py`) copies new NAS thumbnails to `\\SHINERSQL18\001 Master Thumbnail Images`, makes missing thumbnails from Item Docs photos and adds them to the catalogue as source `SQL18_THUMBNAIL` through `dbo.merge_item_thumbnail_locations`. Built 12 October 2026; see `documents/item_image_sources.md`.
- User decisions (12 Oct 2026): SQL18 is its own image source and the NAS rows stay; "not blocked" is Ltd or BV unblocked (never the LLC flag), plus blocked items sold in the last month; network photos only, no SharePoint downloads; each run also copies new NAS thumbnails. Generated thumbnails are not uploaded to SharePoint.
- The script never deletes, never writes to the NAS or Item Docs, and never replaces a marketing thumbnail with a generated one. Keep it that way. `--dry-run` and `--output-dir` write nothing to the server folder or the database.
- List folders with `scan_pictures` (os.scandir), not one stat per file: over the network the per-file version took more than ten minutes for 21,000 files.
- Deployment order: the `SQL18_THUMBNAIL` source constraint (applied; now in `sql/tables/dbo/item_image_locations.sql`) and the procedure first, then the Python. The morning refresh fails (keeping the previous rows) if it scans the SQL18 folder before the constraint allows the new source.

## Inventory cost datasets (finance; simplified 19 October 2026)

- Objects live in data_control's `[finance]` schema (owned by dbo), distinct from the protected separate Finance database. Permanent tables: `inventory_cost_checks`, `inventory_cost_receipts`, `inventory_cost_unadjusted`, `inventory_cost_headers`, `inventory_cost_lines`. Definitions in `sql/tables/finance/`; procedures in `sql/procedures/finance/`. Header rename was applied by the user and verified; the old-name synonym and completed one-off migration are removed.
- One operation across all users, no queue: request procedures acquire the `inventory_cost_operation` transaction application lock; a pending check/header identifies the single operation. The Python worker holds the same resource as a session lock through the whole operation, calls `begin_inventory_cost_operation` once, processes it and exits. Busy submissions are refused. No coordination table, queue-claim procedure or hourly backstop. Requests fail immediately if the job cannot start. A new submission holding the lock can mark an interrupted worker's record failed; an unclaimed launch expires after two minutes. Never expire a live worker by elapsed duration alone.
- `scripts/run_inventory_cost.py` runs on demand through the existing `inventory_cost_requests` SQL Agent job (LP_PROXY, `E:\data_control\data_control`). Request procedures call `finance.start_inventory_cost_job` -> `msdb.dbo.start_inventory_cost_requests_job` (WITH EXECUTE AS OWNER, fixed job). Runtime shiner_reports has only EXECUTE on that bridge in msdb, no general job rights. `sql/database/agent_job_inventory_cost.sql` updates the existing job in place and detaches its schedules without affecting other jobs. `inventory_cost_job_starter.sql` installs the bridge.
- Python `shinerutils/updates/inventory_cost.py` validates NAV rows and sends parameterised JSON (decimal strings preserve precision) to `finance.build_inventory_cost`. It inserts permanent lines, converts at the header's six saved rates and updates totals in one transaction. No staging table, no CREATE/replace/drop cycle. Source query files are `sql/select/shinersql02/inventory_cost_dataset.sql` (Ltd/B.V selected locations, NAV_LIVE) and `sql/select/shinersql04/inventory_cost_dataset.sql` (LLC selected locations, BC_LIVE_USA). Do not reintroduce `inventory_cost_staging` or `claim_inventory_cost_request`.
- Check counting simplified and deployed 19 October 2026: `inventory_cost_checks.sql` on SQL02/SQL04 now selects only company and unposted actual-cost count; duplicate unadjusted item-ledger scans removed. Receipt/unadjusted list SQL is unchanged. The worker takes both warning counts from list lengths and passes them as required `@uninvoiced_lines` / `@unadjusted_entries` to `finance.complete_inventory_cost_check` in the same write transaction. Never call the completion procedure with the old two-parameter signature. The worker fails if any of the three company's blocking counts is missing, duplicated, NULL or negative. Warning review remains before dataset creation. Sixteen worker tests and a rollback-only SQL18 replay (133 receipts / 302 unadjusted, original pass/fail) passed; no source-server queries were run for verification. Manual replay tool: `tools/check_inventory_cost_check_transport.py`. Rollback backup: `C:\ShinerReports\releases\inventory-check-counts-backup-20261019` on SQL18.
- Source deadlock fix deployed 19 October 2026: `_read_source` retries only SQL deadlock 1205 on inventory SELECTs, four total attempts with 1/2/4-second backoff+jitter; each failed helper read closes/rolls back its connection before retry. Never retry writes or arbitrary errors. Detailed errors stay in db_log; source-read failures returned to the portal are concise. The portal sanitises historical raw driver/SQL messages too. Both `inventory_cost_unadjusted.sql` files use grouped positive-stock joins and MAXDOP 1, retaining normal committed reads and all original filters/columns (no NOLOCK). Only source SELECTs were executed; no SQL02/SQL04 object/settings/data mutations. Twenty worker and 372 portal tests passed. Live check 10 for 19 Oct completed: 150 receipt / 913 unadjusted warnings, 916 unposted G/L costs (correctly not passed). No dataset created. Keep the old failed check as history; its page/API message is sanitised. Rollback worker backup: `C:\ShinerReports\releases\inventory-deadlock-backup-20261019`.
- Explicit G/L override added at the user's request on 19 October 2026: latest completed checks with positive unposted costs can be overridden only with explicit `@override_unposted=1`, nonblank `@override_reason` (max 500) and review acknowledgement. Failed/unfinished checks and stale completed checks remain refused; the original is_passed value is never changed. No new permission or table. `inventory_cost_headers` adds reviewed_at, override_reason, override_at; legacy adjustment/posting confirmation timestamps are nullable, historical values retained. New UI uses one review acknowledgement, never a false posting confirmation. Procedure parameters @review_confirmed/@override_unposted/@override_reason default safely for legacy clients. The header's verified creator and override time/reason plus an atomic db_log WARNING record audit the decision. Header constraints require review (or both legacy confirmations) and paired reason/time. Report/API/export metadata discloses overrides. 377 app tests, rollback-only SQL harness with job start disabled, browser consent/technical-failure checks and live API refusal tests passed; no dataset created or source-server queries executed for verification. Rollback source procedure backup: `C:\ShinerReports\releases\inventory-override-backup-20261019`.
- As-of rules unchanged: positive net item-ledger quantity posted through the date, excluding drop shipments; cost is actual plus expected value-entry cost posted through the date, not valuation date. Never use today's Remaining Quantity to reconstruct historical stock. Receipt dates prefer purchases, otherwise positive adjustments. Expected cost is included in cost and kept separately. All six conversion pairs and rate dates are fixed on the header; descriptions unique; multiple datasets can share a date.
- Only actual costs not posted to the G/L block a check. Uninvoiced receipts and entries still Applied Entry to Adjust are warnings. The latter are scoped to the dataset location, 12 months through the date, and items with positive stock there as of that date. The check's receipt invoice quantities come from value entries through the date, not today's receipt balance. Review acknowledgement is required; unposted costs need an explicit audited override or posting in NAV. The app never adjusts or posts NAV costs.
- Check warning lists and completion are transactional. Completed/failed checks more than 30 days old with no dataset are purged by the existing request procedure; checks backing datasets remain. Dataset/check deletion remains explicit, permission-controlled and logged; permanent tables are never recreated. Grants remain per object, never on the entire finance schema.
- NAV SQL is reviewed and unchanged apart from dataset-query filenames in this simplification. Do not run additional SQL02/SQL04 queries without the user's go-ahead. SQL02 is SQL Server 2008 R2: preserve compatibility.
- Deployment verified 19 October 2026: portal Release, worker and nine procedure definitions installed; old synonym/claim procedure absent, five permanent tables and existing ready snapshot intact, no job schedules or staging table. Rollback backups under `C:\ShinerReports\releases\inventory-operation-backup-20261019` on SQL18. No IIS restart. Thirteen offline worker tests and 369 portal tests passed; direct-save rollback test matched all 8,654 existing lines and all currency totals; live cross-session submissions were refused while the lock was held. Runtime shiner_reports can SELECT the renamed header. Do not delete rollback backups as routine cleanup.

## Exclusions & Deductions objects (deployed 15 October 2026)

- The portal's Exclusions & Deductions app (12 Oct 2026) needs `sql/migrations/20261012_add_margin_rule_management.sql` (tables `margin_rule_snapshots`, `margin_rule_snapshot_exclusions`, `margin_rule_snapshot_deductions`, `margin_rule_runs`) and nine procedures: `save_margin_rule_snapshot`, `restore_margin_rule_snapshot`, `add_exclusion_rule`, `delete_exclusion_rule`, `add_deduction_rule`, `delete_deduction_rule`, `reset_sales_exclusion_flags`, `recalculate_sales_deductions`, `run_margin_rule_recalculation`. None had been deployed: the user's first run of the grants file failed with Msg 15151 for all of them. Deployed by the helper at the user's request on 15 Oct 2026 (create only; `update_adjusted_margin` was already live and identical, so it was not redeployed). Verified: all objects exist; the only unresolved references are the `sl` alias in `UPDATE sl ... FROM dbo.sales AS sl` (harmless); the app's runs and snapshots queries run (empty). No check, recalculation or rule change was run. The user ran the margin-rule GRANT lines the same day (verified: SELECT on the four tables, EXECUTE on the seven procedures the portal calls, none on the two sales procedures).

## Historical handover (15 October 2026; inventory architecture superseded above on 19 October)

- Live on shinersql18 data_control: schema `[finance]` (user-created), the five finance tables, the seven `[finance]` procedures, the portal grants (verified) and the SQL Agent job `inventory_cost_requests` (enabled, idle runs succeed and log nothing). The server's checkout `E:\data_control\data_control` was at commit a233f7e; pull again after new commits that touch `scripts/` or `shinerutils/`.
- No real check or dataset has been run yet. The first real request will come from the portal's Inventory Datasets app (dashboard_app); watch `finance.inventory_cost_checks` / `finance.inventory_cost_headers` status and message, `dbo.db_log` (table `inventory_cost`) and the job history. Expected for 30 Sep 2026 from the read-only validation: passes (0 unposted), 133 Ltd receipt lines not invoiced, 185 Ltd entries not cost-adjusted, Ltd expected cost about GBP 107,708.
- The user is not completely happy with the portal app's design (dashboard_app, Inventory Datasets); changes there may need changes to the request procedures. The user replaced the queue model on 19 October 2026; follow the current inventory section above.
- Do not query SQL02/SQL04 beyond read-only SELECTs, and only with the user's go-ahead (user rule, 15 Oct 2026).
- First real run (15 Oct 2026, from the portal preview): check 1 for 30 Sep 2026 passed (133 receipt lines not invoiced, 229 entries not cost-adjusted) and dataset "September 2026" was built (8,654 lines, GBP 6,960,853.35).
- ON-DEMAND START (user decision, 15 Oct 2026; the every-minute polling was rejected): `request_inventory_cost_check` and `request_inventory_cost` call `finance.start_inventory_cost_job` straight after writing the request row, which calls `msdb.dbo.start_inventory_cost_requests_job` (WITH EXECUTE AS OWNER, fixed job name, no parameters); the portal's login `shiner_reports` has a user in msdb with EXECUTE on that one procedure and nothing else. Created by `sql/database/inventory_cost_job_starter.sql` (sysadmin). A certificate-signed version was tried first and dropped: the signature does not reach into msdb's own `sp_start_job`, which then reported the job as not existing (error 14262); the starter script removes that setup. A failed start (other than 22022, already running) is written to db_log as a WARNING with SQL Server's message, and the request waits for the job's hourly backstop run (`sql/database/agent_job_inventory_cost.sql`, re-run once the start works). The request row is the record the page follows, not a waiting list. LIVE and verified 15 Oct 2026: the user ran `inventory_cost_job_starter.sql` (shiner_reports in msdb: CONNECT and EXECUTE on that one procedure only); a check requested as shiner_reports at 16:28:40 started at 16:28:44; the job's schedule was then changed in place to the hourly backstop `inventory_cost_requests_hourly_backstop` (06:00-20:00), the same as the job script. Test checks 2-5 (30 Sep, 14, 13 and 12 Oct, requested by "Signing test"/"Start test") remain; unless a dataset uses them they are removed after 30 days. Check 3 (14 Oct) did not pass: item costs posted that recently were not yet all on the G/L, as expected.
- Entries not cost-adjusted are also limited to items with stock at the location at the end of the as-of date (user, 15 Oct 2026; `inventory_cost_checks.sql` and `inventory_cost_unadjusted.sql` on both servers, validated read-only: at 30 Sep 2026 all 302 Ltd entries of the last 12 months were for items in stock, so the filter guards rather than trims). The Python job reads these files from the server's checkout: pull after changing them.
- `finance.delete_inventory_cost_check` (deployed 15 Oct 2026): permanently deletes a check and its warning lists from the portal, with db_log; refuses a check a dataset was made from or one waiting or running. Its GRANT EXECUTE to shiner_reports is in `grants_shiner_reports_portal.sql` and must be run by a db_owner.
- Check retention (user decision, 15 Oct 2026): `request_inventory_cost_check` deletes complete or failed checks that finished more than 30 days ago and that no dataset was made from (their warning lists go with them), writing one db_log INFO record; checks behind a dataset are kept.
- Exclusions & Deductions objects were deployed the same day (see that section); no rule change or recalculation has been run.


- Inventory dataset scope (19 Oct): checks.scope_json stores canonical per-entity selections; null locations = All, an empty-string code = blank. Source SELECTs accept date plus bound XML and group quantities/costs/receipt dates per entity/location/item. G/L counts and warnings follow scope. Lines PK includes location_code; build rejects rows outside the check scope. Existing checks retain legacy BRISTOL/3PL/POMONA scope. No new queue, catalogue table or source-server mutation.

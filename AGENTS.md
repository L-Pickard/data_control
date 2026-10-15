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

## Inventory cost datasets (finance, started 15 October 2026)

- Everything lives in the `[finance]` schema (user choice, 15 Oct 2026, for finance's permanent records now and later; owned by `[dbo]` for ownership chaining; not related to the separate Finance database): tables in `sql/tables/finance/`, procedures `[finance].[...]` in `sql/procedures/`, Python writes with `schema="finance"`. Grants stay per object, never `SCHEMA::[finance]`, so later finance tables are not exposed to the portal by default.

- Purpose: finance creates fixed inventory cost datasets as at a chosen date from the portal (an Inventory Datasets app, not yet built); the portal's Inventory Cost report will show datasets only, joining live `items`/`brands` for names. Tables (written 15 Oct 2026, names chosen by the user, NOT yet deployed): `sql/tables/finance/inventory_cost_checks.sql` (checks), `inventory_cost_receipts.sql` (receipt lines not invoiced, per check), `inventory_cost_unadjusted.sql` (entries not adjusted, per check), `inventory_cost.sql` (dataset header), `inventory_cost_lines.sql` (dataset facts) hold permanent finance data: create-only files that never drop; change them with migrations. `inventory_cost_staging.sql` follows `sales_staging`: the job writes it, the build procedure inserts from it and drops it after a successful insert.
- Flow: a check for an as-of date (requested from the portal, run by a SQL Agent job reading NAV: Ltd BRISTOL, B.V 3PL on SQL02, LLC POMONA on SQL04) must pass with zero value entries (on or before the date) whose actual cost is not posted to the G/L; receipt lines not invoiced by the date and item ledger entries still "Applied Entry to Adjust" (FIFO costing) are listed as warnings. Then the person ticks "Item adjusting cost complete" and "Item costs posted to G/L", gives a unique description and the exchange rates (latest, four-week average or manual; all six pairs stored on the header), and requests the dataset: the job reads NAV as at the date into staging, and a build procedure moves it into the lines with GBP/EUR/USD costs in one transaction.
- As-of rules: quantity = item ledger quantity posted on or before the date (not Remaining Quantity, which is today's state); cost = value entry actual plus expected cost with posting date on or before the date (user decision, 15 Oct 2026: posting date, not valuation date, so a dataset agrees with the G/L inventory balance at that date; an adjustment NAV posts into a later open period because the as-of period was closed belongs to the later period); receipts as `item_inventory_costs` but limited to the date. The check's not-invoiced test uses item ledger receipts and their invoiced value entries up to the date, not today's "Qty. Rcd. Not Invoiced".
- User decisions: several datasets may share an as-of date; descriptions unique; the check must pass to continue (only the G/L posting blocks); deleting a dataset is permanent (cascades to lines); lines reference `dbo.items` (items with stock are never deleted).
- Do not run queries on shinersql02 or shinersql04 for this work until the user has reviewed them (user, 15 Oct 2026).
- NAV queries (written 15 Oct 2026, NOT yet run; each takes one `?` = the as-of date, like sales.sql): `sql/select/shinersql02/` (Ltd + B.V) and `sql/select/shinersql04/` (LLC) `inventory_cost_receipts.sql` (receipt lines not fully invoiced by the date, for `inventory_cost_receipts`), `inventory_cost_unadjusted.sql` (flagged entries, for `inventory_cost_unadjusted`), `inventory_cost_checks.sql` (per company, every location: item ledger entries still "Applied Entry to Adjust" and value entries whose actual cost differs from "Cost Posted to G/L", up to the date) and `inventory_cost_staging.sql` (the dataset: item ledger quantity and value entry actual cost posted up to the date at the company's location, receipts as `item_inventory_costs`). Validated read-only on 15 Oct 2026 with the user's permission (SELECT only; shinersql02 is SQL Server 2008 R2, so no FORMAT/IIF/STRING_AGG): every field exists on NAV and BC; for 30 Sep 2026 the receipts query found 133 Ltd lines (26 = exactly the lines today's "Qty. Rcd. Not Invoiced" shows, 107 invoiced on 7 Oct), none for B.V or LLC; the dataset query for today matched item_inventory_costs exactly for B.V, within a few units for LLC (activity since the morning load), and for Ltd differs only by activity since the load plus 17 items whose open negative entries net their stock to zero (Remaining Quantity counts them, the ledger total does not). The SQL02 dataset query takes 60-120 s, the receipts query up to 60 s. User decisions after validation (15 Oct 2026): (1) entries still "Applied Entry to Adjust" (1,281 Ltd and 316 B.V company-wide, back to 2013, a few added every month and never cleared) are a WARNING list (`inventory_cost_unadjusted` table and query) scoped to the dataset location and the 12 months up to the as-of date; (2) dataset cost = actual + expected cost posted by the date (as NAV values interim inventory), with `expected_cost` kept separately on staging and lines, so receipts not invoiced by the date are a WARNING too. Only value entries not posted to the G/L block a check (`is_passed`). Re-validated read-only for 30 Sep 2026: Ltd 185 flagged entries in scope (171 purchases still holding 27,845 units), B.V and LLC none; Ltd expected cost £107,707.86 on 135 items, matching the 133 receipt lines not invoiced by then; nothing unposted for any company.
- Job and procedures (written and deployed 15 Oct 2026; tests in `tools/test_inventory_cost.py`, offline): the portal only queues, through `request_inventory_cost_check` (as-of date) and `request_inventory_cost` (passed latest check, description, both confirmations, rate method and all six rates; returns outcome/message/id rows like the margin-rule procedures), and deletes through `delete_inventory_cost` (permanent, refuses while loading, writes db_log). It cannot start jobs (no msdb rights, no signed procedure): a SQL Agent job runs `python scripts/run_inventory_cost.py` every minute, which claims requests in order (`claim_inventory_cost_request`; anything running over 3 hours is marked failed as interrupted), runs `shinerutils/updates/inventory_cost.py` (check: warning lists + `complete_inventory_cost_check` in one transaction; dataset: validate, write `inventory_cost_staging` with replace, `build_inventory_cost`, which checks the staging rows, converts at the header's rates, completes the header and drops staging) and on any error calls `fail_inventory_cost_request` with the reason. With nothing queued the script writes nothing to db_log. Grants in `grants_shiner_reports_portal.sql` (SELECT on the five tables, EXECUTE on the three portal procedures), run by the user on 15 Oct 2026 and verified.
- Deployed 15 Oct 2026 on shinersql18 data_control: the `[finance]` schema (by the user), the five permanent tables and the seven procedures (by the helper, at the user's request; verified: 5 tables, 7 procedures, 9 foreign keys, 13 check constraints; only `build_inventory_cost`'s reference to the staging table is unresolved, as expected). Grants run by the user the same day (verified). The Agent job was created, test-run and enabled by the user the same day (repository pulled on the server at a233f7e; idle runs succeed in 4-9 s and write nothing to db_log). It is scripted in `sql/database/agent_job_inventory_cost.sql` (job `inventory_cost_requests`: PowerShell step under LP_PROXY = SHINER\leo.pickard, E:\data_control\data_control with its venv, every minute 06:00-20:00, like owtanet_ftp_file_processing; the script creates it disabled; pull the repository on the server before running it; needs a sysadmin). The finance tables reference `dbo.items`, `dbo.entities` and `dbo.brands`, so re-running those DROP/CREATE table files now fails while datasets exist (as it already did for `item_inventory_costs` and `inventory`).
- Deployment order: `sql/database/schema_finance.sql` (db_owner), the five permanent table files in this order: checks, receipts, unadjusted, inventory_cost, lines (staging is created by the job), the seven procedure files, the grants (db_owner), then the Agent job on shinersql18 (one step, the venv's python running `scripts/run_inventory_cost.py`, every minute; its account needs read access to NAV_LIVE on SQL02 and BC_LIVE_USA on SQL04, as the other loaders).
- Still to build: the portal app (Inventory Datasets) and switching the Inventory Cost report to datasets.

## Exclusions & Deductions objects (deployed 15 October 2026)

- The portal's Exclusions & Deductions app (12 Oct 2026) needs `sql/migrations/20261012_add_margin_rule_management.sql` (tables `margin_rule_snapshots`, `margin_rule_snapshot_exclusions`, `margin_rule_snapshot_deductions`, `margin_rule_runs`) and nine procedures: `save_margin_rule_snapshot`, `restore_margin_rule_snapshot`, `add_exclusion_rule`, `delete_exclusion_rule`, `add_deduction_rule`, `delete_deduction_rule`, `reset_sales_exclusion_flags`, `recalculate_sales_deductions`, `run_margin_rule_recalculation`. None had been deployed: the user's first run of the grants file failed with Msg 15151 for all of them. Deployed by the helper at the user's request on 15 Oct 2026 (create only; `update_adjusted_margin` was already live and identical, so it was not redeployed). Verified: all objects exist; the only unresolved references are the `sl` alias in `UPDATE sl ... FROM dbo.sales AS sl` (harmless); the app's runs and snapshots queries run (empty). No check, recalculation or rule change was run. The user ran the margin-rule GRANT lines the same day (verified: SELECT on the four tables, EXECUTE on the seven procedures the portal calls, none on the two sales procedures).

## Handover (15 October 2026, end of a Claude Code session)

- Live on shinersql18 data_control: schema `[finance]` (user-created), the five finance tables, the seven `[finance]` procedures, the portal grants (verified) and the SQL Agent job `inventory_cost_requests` (enabled, idle runs succeed and log nothing). The server's checkout `E:\data_control\data_control` was at commit a233f7e; pull again after new commits that touch `scripts/` or `shinerutils/`.
- No real check or dataset has been run yet. The first real request will come from the portal's Inventory Datasets app (dashboard_app); watch `finance.inventory_cost_checks` / `finance.inventory_cost` status and message, `dbo.db_log` (table `inventory_cost`) and the job history. Expected for 30 Sep 2026 from the read-only validation: passes (0 unposted), 133 Ltd receipt lines not invoiced, 185 Ltd entries not cost-adjusted, Ltd expected cost about GBP 107,708.
- The user is not completely happy with the portal app's design (dashboard_app, Inventory Datasets); changes there may need changes to the request procedures. Keep the queue model (portal queues, job runs) unless the user decides otherwise.
- Do not query SQL02/SQL04 beyond read-only SELECTs, and only with the user's go-ahead (user rule, 15 Oct 2026).
- First real run (15 Oct 2026, from the portal preview): check 1 for 30 Sep 2026 passed (133 receipt lines not invoiced, 229 entries not cost-adjusted) and dataset "September 2026" was built (8,654 lines, GBP 6,960,853.35).
- ON-DEMAND START (user decision, 15 Oct 2026; the every-minute polling was rejected): `request_inventory_cost_check` and `request_inventory_cost` call `finance.start_inventory_cost_job` straight after writing the request row, which calls `msdb.dbo.start_inventory_cost_requests_job` (WITH EXECUTE AS OWNER, fixed job name, no parameters); the portal's login `shiner_reports` has a user in msdb with EXECUTE on that one procedure and nothing else. Created by `sql/database/inventory_cost_job_starter.sql` (sysadmin). A certificate-signed version was tried first and dropped: the signature does not reach into msdb's own `sp_start_job`, which then reported the job as not existing (error 14262); the starter script removes that setup. A failed start (other than 22022, already running) is written to db_log as a WARNING with SQL Server's message, and the request waits for the job's hourly backstop run (`sql/database/agent_job_inventory_cost.sql`, re-run once the start works). The request row is the record the page follows, not a waiting list. LIVE and verified 15 Oct 2026: the user ran `inventory_cost_job_starter.sql` (shiner_reports in msdb: CONNECT and EXECUTE on that one procedure only); a check requested as shiner_reports at 16:28:40 started at 16:28:44; the job's schedule was then changed in place to the hourly backstop `inventory_cost_requests_hourly_backstop` (06:00-20:00), the same as the job script. Test checks 2-5 (30 Sep, 14, 13 and 12 Oct, requested by "Signing test"/"Start test") remain; unless a dataset uses them they are removed after 30 days. Check 3 (14 Oct) did not pass: item costs posted that recently were not yet all on the G/L, as expected.
- Entries not cost-adjusted are also limited to items with stock at the location at the end of the as-of date (user, 15 Oct 2026; `inventory_cost_checks.sql` and `inventory_cost_unadjusted.sql` on both servers, validated read-only: at 30 Sep 2026 all 302 Ltd entries of the last 12 months were for items in stock, so the filter guards rather than trims). The Python job reads these files from the server's checkout: pull after changing them.
- `finance.delete_inventory_cost_check` (deployed 15 Oct 2026): permanently deletes a check and its warning lists from the portal, with db_log; refuses a check a dataset was made from or one waiting or running. Its GRANT EXECUTE to shiner_reports is in `grants_shiner_reports_portal.sql` and must be run by a db_owner.
- Check retention (user decision, 15 Oct 2026): `request_inventory_cost_check` deletes complete or failed checks that finished more than 30 days ago and that no dataset was made from (their warning lists go with them), writing one db_log INFO record; checks behind a dataset are kept.
- Exclusions & Deductions objects were deployed the same day (see that section); no rule change or recalculation has been run.


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

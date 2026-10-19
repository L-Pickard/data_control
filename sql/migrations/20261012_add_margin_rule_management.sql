-- Tables behind the Shiner Reports portal's Exclusions & Deductions app (12 October 2026).
--   margin_rule_snapshots (+ _exclusions, _deductions): saved copies of dbo.exclusions and dbo.deductions. One is
--     saved before every change, restore and recalculation, and on demand; any of them can be restored.
--   margin_rule_runs: one row per check or recalculation of dbo.sales against the rules, with what it found.
-- Nothing existing is changed. Safe to run again. Run as a db_owner, then the procedures listed at the end and
-- sql/database/grants_shiner_reports_portal.sql.
USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

SET XACT_ABORT ON;

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.margin_rule_snapshots', N'U') IS NULL
	CREATE TABLE [dbo].[margin_rule_snapshots] (
		 [snapshot_id] INT IDENTITY(1, 1) NOT NULL
		,[taken_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_margin_rule_snapshots_taken_at] DEFAULT (SYSDATETIME())
		,[taken_by] NVARCHAR(200) NOT NULL
		-- Why it was saved: on demand, or before a change of that kind.
		,[reason] NVARCHAR(30) NOT NULL
		,[description] NVARCHAR(400) NOT NULL CONSTRAINT [DF_margin_rule_snapshots_description] DEFAULT (N'')
		,[exclusion_rows] INT NOT NULL CONSTRAINT [DF_margin_rule_snapshots_exclusion_rows] DEFAULT (0)
		,[deduction_rows] INT NOT NULL CONSTRAINT [DF_margin_rule_snapshots_deduction_rows] DEFAULT (0)
		,CONSTRAINT [PK_margin_rule_snapshots] PRIMARY KEY CLUSTERED ([snapshot_id])
		,CONSTRAINT [CK_margin_rule_snapshots_reason] CHECK ([reason] IN (N'manual', N'add', N'delete', N'restore', N'recalculation'))
		);

-- The copies have no foreign key to dbo.entities: a copy must outlive changes to the tables it describes.
IF OBJECT_ID(N'dbo.margin_rule_snapshot_exclusions', N'U') IS NULL
	CREATE TABLE [dbo].[margin_rule_snapshot_exclusions] (
		 [snapshot_id] INT NOT NULL
		,[entity] NVARCHAR(20) NOT NULL
		,[type] NVARCHAR(20) NOT NULL
		,[table_name] NVARCHAR(20) NOT NULL
		,[id] NVARCHAR(20) NOT NULL
		,[brand_id] NVARCHAR(20) NOT NULL
		,CONSTRAINT [PK_margin_rule_snapshot_exclusions] PRIMARY KEY CLUSTERED ([snapshot_id], [entity], [type], [table_name], [id], [brand_id])
		,CONSTRAINT [FK_margin_rule_snapshot_exclusions_snapshot] FOREIGN KEY ([snapshot_id])
			REFERENCES [dbo].[margin_rule_snapshots] ([snapshot_id]) ON DELETE CASCADE
		);

IF OBJECT_ID(N'dbo.margin_rule_snapshot_deductions', N'U') IS NULL
	CREATE TABLE [dbo].[margin_rule_snapshot_deductions] (
		 [snapshot_id] INT NOT NULL
		,[deduction_id] NVARCHAR(20) NOT NULL
		,[deduction_type] NVARCHAR(50) NOT NULL
		,[deduction_sub_type] NVARCHAR(30) NOT NULL
		,[deduction_entity] NVARCHAR(20) NOT NULL
		,[deduction_value] DECIMAL(38, 20) NOT NULL
		,CONSTRAINT [PK_margin_rule_snapshot_deductions] PRIMARY KEY CLUSTERED ([snapshot_id], [deduction_id], [deduction_type], [deduction_sub_type], [deduction_entity])
		,CONSTRAINT [FK_margin_rule_snapshot_deductions_snapshot] FOREIGN KEY ([snapshot_id])
			REFERENCES [dbo].[margin_rule_snapshots] ([snapshot_id]) ON DELETE CASCADE
		);

IF OBJECT_ID(N'dbo.margin_rule_runs', N'U') IS NULL
	CREATE TABLE [dbo].[margin_rule_runs] (
		 [run_id] INT IDENTITY(1, 1) NOT NULL
		,[requested_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_margin_rule_runs_requested_at] DEFAULT (SYSDATETIME())
		,[requested_by] NVARCHAR(200) NOT NULL
		-- 0 = a check (counts what would change), 1 = sales rows were changed.
		,[apply_changes] BIT NOT NULL
		-- Sales posted on or after this date; NULL = the whole table.
		,[start_date] DATE NULL
		,[reset_flags] BIT NOT NULL
		,[recalculate_margin] BIT NOT NULL
		,[update_adjusted_margin] BIT NOT NULL
		-- A row left as 'running' while nothing holds the application lock was interrupted (its changes were rolled back).
		,[status] NVARCHAR(20) NOT NULL CONSTRAINT [DF_margin_rule_runs_status] DEFAULT (N'running')
		,[finished_at] DATETIME2(0) NULL
		,[rows_in_scope] INT NULL
		,[flag_rows] INT NULL
		,[margin_rows] INT NULL
		,[gbp_margin_change] DECIMAL(38, 6) NULL
		,[snapshot_id] INT NULL
		,[error_message] NVARCHAR(2000) NULL
		,CONSTRAINT [PK_margin_rule_runs] PRIMARY KEY CLUSTERED ([run_id])
		,CONSTRAINT [CK_margin_rule_runs_status] CHECK ([status] IN (N'running', N'completed', N'failed'))
		);

COMMIT TRANSACTION;

GO

SELECT o.[name], o.[create_date]
FROM sys.objects AS o
WHERE o.[name] LIKE N'margin[_]rule[_]%' AND o.[type] = 'U'
ORDER BY o.[name];

-- Next, in this order (each is CREATE OR ALTER):
--   sql/procedures/dbo/save_margin_rule_snapshot.sql
--   sql/procedures/dbo/restore_margin_rule_snapshot.sql
--   sql/procedures/dbo/add_exclusion_rule.sql
--   sql/procedures/dbo/delete_exclusion_rule.sql
--   sql/procedures/dbo/add_deduction_rule.sql
--   sql/procedures/dbo/delete_deduction_rule.sql
--   sql/procedures/dbo/reset_sales_exclusion_flags.sql
--   sql/procedures/dbo/recalculate_sales_deductions.sql
--   sql/procedures/dbo/run_margin_rule_recalculation.sql
--   sql/database/grants_shiner_reports_portal.sql

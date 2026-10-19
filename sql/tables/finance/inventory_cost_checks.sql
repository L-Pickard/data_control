USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Inventory cost dataset pre-checks: one row per check a finance user asks for in the portal (Inventory Datasets app)
-- for an as-of date. The row is also the job's request: the portal's request procedure inserts it as 'requested' and
-- starts the SQL Agent job, which reads NAV for the selected entities and locations, sets it to
-- 'running', writes the not-invoiced receipt lines to finance.inventory_cost_receipts and the flagged entries to
-- finance.inventory_cost_unadjusted, and completes it with the three counts, all as at the end of as_of_date:
--   uninvoiced_lines   purchase receipt lines posted on or before as_of_date whose quantity was not fully invoiced by
--                      as_of_date (item ledger entries and their invoiced value entries, not today's
--                      "Qty. Rcd. Not Invoiced", so a receipt invoiced after the date still counts)
--   unadjusted_entries item ledger entries still flagged "Applied Entry to Adjust" (FIFO costing: Adjust Cost - Item
--                      Entries has not reached them), at the dataset locations and posted in the 12 months up to
--                      as_of_date
--   unposted_entries   value entries posted on or before as_of_date, selected locations, whose actual cost differs from
--                      the cost posted to the G/L (Post Inventory Cost to G/L has not finished for them)
-- Only unposted_entries blocks (user decisions, 15 Oct 2026): a check passes (is_passed) when it completed with no
-- unposted entries. Receipts not invoiced by the date are a warning, because the dataset includes their expected
-- cost (as NAV values interim inventory); flagged entries are a warning, because NAV keeps a few every month and
-- never clears them. The portal shows both lists. A dataset can only be created from a passed check for the same
-- as-of date.
-- requested_by_id is the portal person's id (Windows SID, portal.users.user_id); requested_by their display name.
-- Permanent finance data: create only when missing. This file never drops the table. Deploy changes with a migration.

IF OBJECT_ID(N'[finance].[inventory_cost_checks]', N'U') IS NULL
BEGIN
	CREATE TABLE [finance].[inventory_cost_checks] (
		 [check_id] INT IDENTITY(1, 1) NOT NULL
		,[as_of_date] DATE NOT NULL
        ,[scope_json] NVARCHAR(MAX) NOT NULL CONSTRAINT DF_inventory_cost_checks_scope DEFAULT (N'[{"entity":"Shiner Ltd","locations":["BRISTOL"]},{"entity":"Shiner B.V","locations":["3PL"]},{"entity":"Shiner LLC","locations":["POMONA"]}]')
        ,CONSTRAINT CK_inventory_cost_checks_scope CHECK (ISJSON(scope_json)=1)
		,[status] NVARCHAR(20) NOT NULL CONSTRAINT [DF_inventory_cost_checks_status] DEFAULT (N'requested')
		,[requested_by_id] NVARCHAR(184) NOT NULL
		,[requested_by] NVARCHAR(256) NOT NULL
		,[requested_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_inventory_cost_checks_requested_at] DEFAULT (SYSDATETIME())
		,[started_at] DATETIME2(0) NULL
		,[completed_at] DATETIME2(0) NULL
		,[uninvoiced_lines] INT NULL
		,[unadjusted_entries] INT NULL
		,[unposted_entries] INT NULL
		,[message] NVARCHAR(4000) NULL
		,[is_passed] AS CAST(CASE
					WHEN [status] = N'complete'
						AND [unposted_entries] = 0
						THEN 1
					ELSE 0
					END AS BIT)
		,CONSTRAINT [PK_inventory_cost_checks] PRIMARY KEY CLUSTERED ([check_id])
		,CONSTRAINT [CK_inventory_cost_checks_status] CHECK ([status] IN (N'requested', N'running', N'complete', N'failed'))
		-- The as-of date cannot be in the future.
		,CONSTRAINT [CK_inventory_cost_checks_as_of_date] CHECK ([as_of_date] <= CAST([requested_at] AS DATE))
		,CONSTRAINT [CK_inventory_cost_checks_complete] CHECK (
			[status] <> N'complete'
			OR (
				[completed_at] IS NOT NULL
				AND [uninvoiced_lines] IS NOT NULL
				AND [unadjusted_entries] IS NOT NULL
				AND [unposted_entries] IS NOT NULL
				)
			)
		,CONSTRAINT [CK_inventory_cost_checks_counts] CHECK (
			[uninvoiced_lines] >= 0
			AND [unadjusted_entries] >= 0
			AND [unposted_entries] >= 0
			)
		);

	CREATE NONCLUSTERED INDEX [IX_inventory_cost_checks_as_of_date]
		ON [finance].[inventory_cost_checks] ([as_of_date], [check_id] DESC)
		INCLUDE ([status], [completed_at], [uninvoiced_lines], [unadjusted_entries], [unposted_entries]);
END

GO

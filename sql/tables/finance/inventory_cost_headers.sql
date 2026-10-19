USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

-- Inventory cost datasets (header): one row per dataset a finance user creates in the portal (Inventory Datasets app).
-- A dataset is the stock and its cost at the end of as_of_date for the entities and locations recorded on its check, read
-- from NAV by the dataset job: actual cost plus expected cost (received, not yet invoiced) posted by the date, in each
-- company's currency and converted at the rates stored here. The
-- Inventory Cost report shows datasets only; its lines are finance.inventory_cost_lines.
--   check_id      the completed check (finance.inventory_cost_checks, same as_of_date: passed or explicitly overridden) the
--                 dataset was created from; its warnings (receipts not invoiced, entries not adjusted) stay with it
--   status        requested (inserted by the request procedure, which starts the job), loading (the job is reading
--                 NAV and passes rows directly to the build procedure), complete (lines, line_count and totals written in one
--                 transaction by the build procedure) or failed (message says why; no lines)
--   *_confirmed_at when the creator ticked "Item adjusting cost complete" and "Item costs posted to G/L"
--   rate_method   latest (latest daily rate of each pair), fourWeeks (average of the daily rates over the 28 days up
--                 to the request) or manual; rates_from/rates_to are the dates of the rates used (NULL for manual)
--   gbp_eur ...   one unit of the first currency in the second, all six pairs (the cost_* columns of the lines are
--                 the line's cost in its company's currency times the pair into GBP, EUR and USD)
-- Several datasets may share an as-of date (user decision, 15 Oct 2026); descriptions are unique. Deleting a dataset
-- is permanent (user decision) and removes its lines (ON DELETE CASCADE).
-- created_by_id is the portal person's id (Windows SID, portal.users.user_id); created_by their display name.
-- Permanent finance data: create only when missing. This file never drops the table. Deploy changes with a migration.

IF OBJECT_ID(N'[finance].[inventory_cost_headers]', N'U') IS NULL
BEGIN
	CREATE TABLE [finance].[inventory_cost_headers] (
		 [dataset_id] INT IDENTITY(1, 1) NOT NULL
		,[description] NVARCHAR(100) NOT NULL
		,[as_of_date] DATE NOT NULL
		,[check_id] INT NOT NULL
		,[status] NVARCHAR(20) NOT NULL CONSTRAINT [DF_inventory_cost_status] DEFAULT (N'requested')
		,[created_by_id] NVARCHAR(184) NOT NULL
		,[created_by] NVARCHAR(256) NOT NULL
		,[created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_inventory_cost_created_at] DEFAULT (SYSDATETIME())
		,[started_at] DATETIME2(0) NULL
		,[completed_at] DATETIME2(0) NULL
		,[cost_adjusted_confirmed_at] DATETIME2(0) NULL
		,[posted_to_gl_confirmed_at] DATETIME2(0) NULL
        ,[reviewed_at] DATETIME2(0) NULL
        ,[override_reason] NVARCHAR(500) NULL
        ,[override_at] DATETIME2(0) NULL
		,[rate_method] NVARCHAR(20) NOT NULL
		,[rates_from] DATE NULL
		,[rates_to] DATE NULL
		,[gbp_eur] DECIMAL(38, 20) NOT NULL
		,[gbp_usd] DECIMAL(38, 20) NOT NULL
		,[eur_gbp] DECIMAL(38, 20) NOT NULL
		,[eur_usd] DECIMAL(38, 20) NOT NULL
		,[usd_gbp] DECIMAL(38, 20) NOT NULL
		,[usd_eur] DECIMAL(38, 20) NOT NULL
		,[line_count] INT NULL
		,[total_gbp] DECIMAL(38, 20) NULL
		,[total_eur] DECIMAL(38, 20) NULL
		,[total_usd] DECIMAL(38, 20) NULL
		,[message] NVARCHAR(4000) NULL
        ,CONSTRAINT [CK_inventory_cost_override] CHECK ((override_reason IS NULL AND override_at IS NULL) OR (override_reason IS NOT NULL AND LEN(LTRIM(RTRIM(override_reason)))>0 AND override_at IS NOT NULL))
        ,CONSTRAINT [CK_inventory_cost_review] CHECK (reviewed_at IS NOT NULL OR (cost_adjusted_confirmed_at IS NOT NULL AND posted_to_gl_confirmed_at IS NOT NULL))
		,CONSTRAINT [PK_inventory_cost] PRIMARY KEY CLUSTERED ([dataset_id])
		,CONSTRAINT [UQ_inventory_cost_description] UNIQUE ([description])
		,CONSTRAINT [FK_inventory_cost_check] FOREIGN KEY ([check_id]) REFERENCES [finance].[inventory_cost_checks] ([check_id])
		,CONSTRAINT [CK_inventory_cost_description] CHECK (LEN(LTRIM(RTRIM([description]))) > 0)
		,CONSTRAINT [CK_inventory_cost_status] CHECK ([status] IN (N'requested', N'loading', N'complete', N'failed'))
		,CONSTRAINT [CK_inventory_cost_as_of_date] CHECK ([as_of_date] <= CAST([created_at] AS DATE))
		,CONSTRAINT [CK_inventory_cost_rate_method] CHECK (
			(
				[rate_method] IN (N'latest', N'fourWeeks')
				AND [rates_from] IS NOT NULL
				AND [rates_to] IS NOT NULL
				AND [rates_from] <= [rates_to]
				)
			OR (
				[rate_method] = N'manual'
				AND [rates_from] IS NULL
				AND [rates_to] IS NULL
				)
			)
		,CONSTRAINT [CK_inventory_cost_rates] CHECK (
			[gbp_eur] > 0
			AND [gbp_usd] > 0
			AND [eur_gbp] > 0
			AND [eur_usd] > 0
			AND [usd_gbp] > 0
			AND [usd_eur] > 0
			)
		,CONSTRAINT [CK_inventory_cost_complete] CHECK (
			[status] <> N'complete'
			OR (
				[completed_at] IS NOT NULL
				AND [line_count] IS NOT NULL
				AND [total_gbp] IS NOT NULL
				AND [total_eur] IS NOT NULL
				AND [total_usd] IS NOT NULL
				)
			)
		);

	CREATE NONCLUSTERED INDEX [IX_inventory_cost_as_of_date]
		ON [finance].[inventory_cost_headers] ([as_of_date] DESC, [dataset_id] DESC)
		INCLUDE ([description], [status]);

	CREATE NONCLUSTERED INDEX [IX_inventory_cost_check]
		ON [finance].[inventory_cost_headers] ([check_id]);
END

GO

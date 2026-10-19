USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [dbo].[run_margin_rule_recalculation]
	 @requested_by NVARCHAR(200)
	,@start_date DATE = NULL
	,@apply BIT = 0
	,@reset_flags BIT = 1
	,@recalculate_margin BIT = 1
	,@update_adjusted_margin BIT = 1
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Brings dbo.sales into line with dbo.exclusions and dbo.deductions after the rules have changed. Started by the Shiner
Reports portal (Exclusions & Deductions app); it can also be run by hand. Up to three steps, each its own procedure:

  1. @reset_flags            reset_sales_exclusion_flags   exclusion and intercompany flags
  2. @recalculate_margin     recalculate_sales_deductions  royalty, customer rebate, margin (adjusted margin moves with it)
  3. @update_adjusted_margin update_adjusted_margin        the Shiner Ltd part of Shiner B.V adjusted margins

@start_date: only sales posted on or after this date; NULL is the whole table.
@apply = 0 is a check: steps 1 and 2 count what would change and nothing is written to dbo.sales.
@apply = 1 saves a copy of the rules, runs the steps in one transaction (all or nothing) and writes a db_log record.
While it runs, dbo.sales rows it has changed are locked, so reports reading them wait until it finishes.

Each call is one row of dbo.margin_rule_runs, written before the work starts and completed at the end. Only one can
run at a time: the session holds the application lock 'margin_rule_recalculation' meanwhile, and the procedures that
change the rules refuse while it is held. A row left as 'running' with the lock free was interrupted (rolled back).

Returns one row: outcome (ok or refused), message and run_id. Must not be called inside a transaction.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @requested_by = LTRIM(RTRIM(ISNULL(@requested_by, N'')));
	SET @apply = ISNULL(@apply, 0);
	SET @reset_flags = ISNULL(@reset_flags, 0);
	SET @recalculate_margin = ISNULL(@recalculate_margin, 0);
	SET @update_adjusted_margin = ISNULL(@update_adjusted_margin, 0);

	IF @requested_by = N''
		THROW 50101, 'The @requested_by parameter cannot be blank.', 1;

	IF @@TRANCOUNT > 0
		THROW 50103, 'run_margin_rule_recalculation cannot be called inside a transaction.', 1;

	IF @reset_flags = 0
		AND @recalculate_margin = 0
		AND @update_adjusted_margin = 0
	BEGIN
		SELECT N'refused' AS [outcome]
			,N'Choose at least one step.' AS [message]
			,CAST(NULL AS INT) AS [run_id];

		RETURN;

	END;

	DECLARE @lock INT;
	DECLARE @run_id INT;
	DECLARE @snapshot_id INT;
	DECLARE @rows_in_scope INT;
	DECLARE @flag_rows INT;
	DECLARE @margin_rows INT;
	DECLARE @gbp_margin_change DECIMAL(38, 6);
	DECLARE @started_at DATETIME2(7) = SYSDATETIME();
	DECLARE @duration_seconds DECIMAL(38, 20);
	DECLARE @scope NVARCHAR(60) = CASE
			WHEN @start_date IS NULL
				THEN N'the whole sales table'
			ELSE CONCAT(N'sales posted from ', CONVERT(NVARCHAR(10), @start_date, 23))
			END;
	DECLARE @description NVARCHAR(400);
	DECLARE @log_message NVARCHAR(MAX);
	DECLARE @error_message NVARCHAR(2000);

	EXEC @lock = sys.sp_getapplock
		 @Resource = N'margin_rule_recalculation'
		,@LockMode = N'Exclusive'
		,@LockOwner = N'Session'
		,@LockTimeout = 0;

	IF @lock < 0
	BEGIN
		SELECT N'refused' AS [outcome]
			,N'A check or recalculation is already running. Wait for it to finish.' AS [message]
			,CAST(NULL AS INT) AS [run_id];

		RETURN;

	END;

	BEGIN TRY
		INSERT INTO [dbo].[margin_rule_runs] (
			 [requested_by]
			,[apply_changes]
			,[start_date]
			,[reset_flags]
			,[recalculate_margin]
			,[update_adjusted_margin]
			)
		VALUES (
			 @requested_by
			,@apply
			,@start_date
			,@reset_flags
			,@recalculate_margin
			,@update_adjusted_margin
			);

		SET @run_id = CAST(SCOPE_IDENTITY() AS INT);

		SELECT @rows_in_scope = COUNT(*)

		FROM [dbo].[sales] AS sl

		WHERE @start_date IS NULL
			OR sl.[posting_date] >= @start_date

		OPTION (RECOMPILE);

		-- The copy of the rules is saved before the transaction, so the list of copies can be read while the
		-- recalculation holds its locks. It records the rules this run used, whether or not the run succeeds.

		IF @apply = 1
		BEGIN
			SET @description = CONCAT(N'Rules used to recalculate ', @scope);

			EXEC [dbo].[save_margin_rule_snapshot]
				 @taken_by = @requested_by
				,@reason = N'recalculation'
				,@description = @description
				,@return_row = 0
				,@snapshot_id = @snapshot_id OUTPUT;

		END;

		BEGIN TRANSACTION;

		IF @reset_flags = 1
			EXEC [dbo].[reset_sales_exclusion_flags]
				 @start_date = @start_date
				,@apply = @apply
				,@return_row = 0
				,@rows_changed = @flag_rows OUTPUT;

		IF @recalculate_margin = 1
			EXEC [dbo].[recalculate_sales_deductions]
				 @start_date = @start_date
				,@apply = @apply
				,@return_row = 0
				,@rows_changed = @margin_rows OUTPUT
				,@gbp_margin_change = @gbp_margin_change OUTPUT;

		IF @apply = 1
			AND @update_adjusted_margin = 1
			EXEC [dbo].[update_adjusted_margin]
				 @start_date = @start_date;

		IF @apply = 1
		BEGIN
			SET @duration_seconds = CAST(DATEDIFF_BIG(MICROSECOND, @started_at, SYSDATETIME()) / 1000000.0 AS DECIMAL(38, 20));

			SET @log_message = CONCAT(N'Run by ', @requested_by, N' in Shiner Reports for ', @scope, N'. Flags: ', CASE WHEN @reset_flags = 1 THEN CONCAT(@flag_rows,
							N' rows changed') ELSE N'not run' END, N'. Royalty, rebate and margin: ', CASE WHEN @recalculate_margin = 1 THEN CONCAT(@margin_rows,
							N' rows changed, margin change GBP ', @gbp_margin_change) ELSE N'not run' END, N'. Adjusted margin: ', CASE WHEN @update_adjusted_margin = 1 THEN
						N'recalculated' ELSE N'not run' END, N'. The rules used are copy ', @snapshot_id, N'.');

			-- Not the action text of the sales load, so the "data last updated" notes do not read this record.

			EXEC [dbo].[write_db_log]
				 @level = N'SUCCESS'
				,@table = N'sales'
				,@rows = @margin_rows
				,@action = N'recalculate sales from exclusions and deductions'
				,@message = @log_message
				,@duration_seconds = @duration_seconds;

		END;

		COMMIT TRANSACTION;

		UPDATE [dbo].[margin_rule_runs]

		SET [status] = N'completed'
			,[finished_at] = SYSDATETIME()
			,[rows_in_scope] = @rows_in_scope
			,[flag_rows] = @flag_rows
			,[margin_rows] = @margin_rows
			,[gbp_margin_change] = @gbp_margin_change
			,[snapshot_id] = @snapshot_id

		WHERE [run_id] = @run_id;

	END TRY

	BEGIN CATCH
		SET @error_message = LEFT(ERROR_MESSAGE(), 2000);

		IF XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		BEGIN TRY
			IF @run_id IS NOT NULL
				UPDATE [dbo].[margin_rule_runs]

				SET [status] = N'failed'
					,[finished_at] = SYSDATETIME()
					,[rows_in_scope] = @rows_in_scope
					,[error_message] = @error_message

				WHERE [run_id] = @run_id;

			IF @apply = 1
			BEGIN
				SET @duration_seconds = CAST(DATEDIFF_BIG(MICROSECOND, @started_at, SYSDATETIME()) / 1000000.0 AS DECIMAL(38, 20));

				SET @log_message = CONCAT(N'Failed to recalculate ', @scope, N' for ', @requested_by, N'. Nothing was changed. Error: ', @error_message);

				EXEC [dbo].[write_db_log]
					 @level = N'FAILURE'
					,@table = N'sales'
					,@rows = NULL
					,@action = N'recalculate sales from exclusions and deductions'
					,@message = @log_message
					,@duration_seconds = @duration_seconds;

			END;

		END TRY

		BEGIN CATCH
			-- Preserve and rethrow the original error if recording it also fails.
		END CATCH;

		EXEC sys.sp_releaseapplock
			 @Resource = N'margin_rule_recalculation'
			,@LockOwner = N'Session';

		THROW;

	END CATCH;

	EXEC sys.sp_releaseapplock
		 @Resource = N'margin_rule_recalculation'
		,@LockOwner = N'Session';

	SELECT N'ok' AS [outcome]
		,N'' AS [message]
		,@run_id AS [run_id];

END;

GO

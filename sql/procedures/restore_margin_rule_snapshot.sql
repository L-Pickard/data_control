USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [dbo].[restore_margin_rule_snapshot]
	 @snapshot_id INT
	,@restored_by NVARCHAR(200)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Puts dbo.exclusions and dbo.deductions back to a saved copy (save_margin_rule_snapshot). Both tables are replaced in one
transaction, after a copy of what they hold now has been saved, so a restore can itself be undone.

dbo.sales is not touched: run run_margin_rule_recalculation afterwards to bring the stored flags and margins into line.
Returns one row: outcome (ok or refused), message, snapshot_id (the copy saved before the restore).
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @restored_by = LTRIM(RTRIM(ISNULL(@restored_by, N'')));

	IF @restored_by = N''
		THROW 50101, 'The @restored_by parameter cannot be blank.', 1;

	DECLARE @refusal NVARCHAR(400);
	DECLARE @taken_at DATETIME2(0);
	DECLARE @description NVARCHAR(400);
	DECLARE @saved_id INT;
	DECLARE @exclusion_rows INT;
	DECLARE @deduction_rows INT;
	DECLARE @log_message NVARCHAR(MAX);
	DECLARE @transaction_started BIT = 0;

	SELECT @taken_at = sn.[taken_at]

	FROM [dbo].[margin_rule_snapshots] AS sn

	WHERE sn.[snapshot_id] = @snapshot_id;

	IF @taken_at IS NULL
		SET @refusal = N'That saved copy no longer exists.';
	ELSE IF APPLOCK_TEST(N'public', N'margin_rule_recalculation', N'Exclusive', N'Session') = 0
		SET @refusal = N'A recalculation is running. Try again when it has finished.';
	ELSE IF EXISTS (
			SELECT se.[entity]

			FROM [dbo].[margin_rule_snapshot_exclusions] AS se

			WHERE se.[snapshot_id] = @snapshot_id

			UNION ALL

			SELECT sd.[deduction_entity]

			FROM [dbo].[margin_rule_snapshot_deductions] AS sd

			WHERE sd.[snapshot_id] = @snapshot_id

			EXCEPT

			SELECT en.[entity]

			FROM [dbo].[entities] AS en
			)
		SET @refusal = N'That saved copy names a company that is no longer in the entities table, so it cannot be restored.';

	IF @refusal IS NOT NULL
	BEGIN
		SELECT N'refused' AS [outcome]
			,@refusal AS [message]
			,CAST(NULL AS INT) AS [snapshot_id];

		RETURN;

	END;

	SET @description = CONCAT(N'Before restoring copy ', @snapshot_id, N' (saved ', CONVERT(NVARCHAR(16), @taken_at, 120), N')');

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;

		END;

		EXEC [dbo].[save_margin_rule_snapshot]
			 @taken_by = @restored_by
			,@reason = N'restore'
			,@description = @description
			,@return_row = 0
			,@snapshot_id = @saved_id OUTPUT;

		DELETE FROM [dbo].[exclusions];

		DELETE FROM [dbo].[deductions];

		INSERT INTO [dbo].[exclusions] (
			 [entity]
			,[type]
			,[table_name]
			,[id]
			,[brand_id]
			)
		SELECT se.[entity]
			,se.[type]
			,se.[table_name]
			,se.[id]
			,se.[brand_id]

		FROM [dbo].[margin_rule_snapshot_exclusions] AS se

		WHERE se.[snapshot_id] = @snapshot_id;

		SET @exclusion_rows = @@ROWCOUNT;

		INSERT INTO [dbo].[deductions] (
			 [deduction_id]
			,[deduction_type]
			,[deduction_sub_type]
			,[deduction_entity]
			,[deduction_value]
			)
		SELECT sd.[deduction_id]
			,sd.[deduction_type]
			,sd.[deduction_sub_type]
			,sd.[deduction_entity]
			,sd.[deduction_value]

		FROM [dbo].[margin_rule_snapshot_deductions] AS sd

		WHERE sd.[snapshot_id] = @snapshot_id;

		SET @deduction_rows = @@ROWCOUNT;

		SET @log_message = CONCAT(N'Restored by ', @restored_by, N' from copy ', @snapshot_id, N' (saved ', CONVERT(NVARCHAR(16), @taken_at, 120), N'): ',
				@exclusion_rows, N' exclusion and intercompany rules, ', @deduction_rows, N' deductions. The rules before the restore are copy ', @saved_id, N'.');

		EXEC [dbo].[write_db_log]
			 @level = N'INFO'
			,@table = N'exclusions'
			,@rows = @exclusion_rows
			,@action = N'restore exclusions and deductions from a saved copy'
			,@message = @log_message;

		IF @transaction_started = 1
			COMMIT TRANSACTION;

	END TRY

	BEGIN CATCH
		IF @transaction_started = 1
			AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		THROW;

	END CATCH;

	SELECT N'ok' AS [outcome]
		,CONCAT(N'Copy ', @snapshot_id, N' restored: ', @exclusion_rows, N' exclusion and intercompany rules, ', @deduction_rows, N' deductions.') AS [message]
		,@saved_id AS [snapshot_id];

END;

GO

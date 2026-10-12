USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [dbo].[save_margin_rule_snapshot]
	 @taken_by NVARCHAR(200)
	,@reason NVARCHAR(30) = N'manual'
	,@description NVARCHAR(400) = N''
	,@return_row BIT = 1
	,@snapshot_id INT = NULL OUTPUT
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Saves a copy of dbo.exclusions and dbo.deductions as they are now, so they can be put back with
restore_margin_rule_snapshot. The other margin-rule procedures call it before every change (@return_row = 0); the Shiner
Reports portal calls it when a person saves a copy by hand.

@reason: manual, add, delete, restore or recalculation (what is about to happen). @description: free text shown in the
portal. Returns one row (outcome, message, snapshot_id) unless @return_row = 0.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @taken_by = LTRIM(RTRIM(ISNULL(@taken_by, N'')));

	SET @description = LEFT(LTRIM(RTRIM(ISNULL(@description, N''))), 400);

	IF @taken_by = N''
		THROW 50101, 'The @taken_by parameter cannot be blank.', 1;

	IF ISNULL(@reason, N'') NOT IN (N'manual', N'add', N'delete', N'restore', N'recalculation')
		THROW 50102, 'The @reason parameter must be manual, add, delete, restore or recalculation.', 1;

	DECLARE @transaction_started BIT = 0;
	DECLARE @exclusion_rows INT;
	DECLARE @deduction_rows INT;

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;

		END;

		INSERT INTO [dbo].[margin_rule_snapshots] (
			 [taken_by]
			,[reason]
			,[description]
			)
		VALUES (
			 @taken_by
			,@reason
			,@description
			);

		SET @snapshot_id = CAST(SCOPE_IDENTITY() AS INT);

		-- HOLDLOCK: both copies are of one moment, even if someone changes a rule meanwhile.

		INSERT INTO [dbo].[margin_rule_snapshot_exclusions] (
			 [snapshot_id]
			,[entity]
			,[type]
			,[table_name]
			,[id]
			,[brand_id]
			)
		SELECT @snapshot_id
			,ex.[entity]
			,ex.[type]
			,ex.[table_name]
			,ex.[id]
			,ex.[brand_id]

		FROM [dbo].[exclusions] AS ex WITH (HOLDLOCK);

		SET @exclusion_rows = @@ROWCOUNT;

		INSERT INTO [dbo].[margin_rule_snapshot_deductions] (
			 [snapshot_id]
			,[deduction_id]
			,[deduction_type]
			,[deduction_sub_type]
			,[deduction_entity]
			,[deduction_value]
			)
		SELECT @snapshot_id
			,de.[deduction_id]
			,de.[deduction_type]
			,de.[deduction_sub_type]
			,de.[deduction_entity]
			,de.[deduction_value]

		FROM [dbo].[deductions] AS de WITH (HOLDLOCK);

		SET @deduction_rows = @@ROWCOUNT;

		UPDATE [dbo].[margin_rule_snapshots]

		SET [exclusion_rows] = @exclusion_rows
			,[deduction_rows] = @deduction_rows

		WHERE [snapshot_id] = @snapshot_id;

		IF @transaction_started = 1
			COMMIT TRANSACTION;

	END TRY

	BEGIN CATCH
		IF @transaction_started = 1
			AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		THROW;

	END CATCH;

	IF @return_row = 1
		SELECT N'ok' AS [outcome]
			,CONCAT(N'Copy ', @snapshot_id, N' saved: ', @exclusion_rows, N' exclusion and intercompany rules, ', @deduction_rows, N' deductions.') AS [message]
			,@snapshot_id AS [snapshot_id];

END;

GO

USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [dbo].[delete_deduction_rule]
	 @deduction_id NVARCHAR(20)
	,@deduction_type NVARCHAR(50)
	,@deduction_sub_type NVARCHAR(30) = N''
	,@deduction_entity NVARCHAR(20)
	,@changed_by NVARCHAR(200)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Deletes one row of dbo.deductions (its whole key is given) for the Shiner Reports portal, after saving a copy of the
rules as they are. Sales already loaded keep their royalty and rebate until run_margin_rule_recalculation is run.
Returns one row: outcome (ok or refused) and message.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @changed_by = LTRIM(RTRIM(ISNULL(@changed_by, N'')));

	IF @changed_by = N''
		THROW 50101, 'The @changed_by parameter cannot be blank.', 1;

	SET @deduction_id = ISNULL(@deduction_id, N'');
	SET @deduction_type = ISNULL(@deduction_type, N'');
	SET @deduction_sub_type = ISNULL(@deduction_sub_type, N'');
	SET @deduction_entity = ISNULL(@deduction_entity, N'');

	DECLARE @refusal NVARCHAR(400);
	DECLARE @value DECIMAL(38, 20);
	DECLARE @description NVARCHAR(400);
	DECLARE @log_message NVARCHAR(MAX);
	DECLARE @transaction_started BIT = 0;

	SELECT @value = de.[deduction_value]

	FROM [dbo].[deductions] AS de

	WHERE de.[deduction_id] = @deduction_id
		AND de.[deduction_type] = @deduction_type
		AND de.[deduction_sub_type] = @deduction_sub_type
		AND de.[deduction_entity] = @deduction_entity;

	IF @value IS NULL
		SET @refusal = N'That deduction is no longer in the table.';
	ELSE IF APPLOCK_TEST(N'public', N'margin_rule_recalculation', N'Exclusive', N'Session') = 0
		SET @refusal = N'A recalculation is running. Try again when it has finished.';

	IF @refusal IS NOT NULL
	BEGIN
		SELECT N'refused' AS [outcome]
			,@refusal AS [message];

		RETURN;

	END;

	-- The rate is part of the description, so the row can be added again from the history by hand.

	SET @description = CONCAT(N'Before deleting ', @deduction_type, N': ', @deduction_entity, N', ', @deduction_id, CASE WHEN @deduction_sub_type <> N'' THEN CONCAT(N', ',
					@deduction_sub_type) ELSE N'' END, N', ', CAST(CAST(@value * 100 AS DECIMAL(9, 4)) AS NVARCHAR(20)), N'%');

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;

		END;

		EXEC [dbo].[save_margin_rule_snapshot]
			 @taken_by = @changed_by
			,@reason = N'delete'
			,@description = @description
			,@return_row = 0;

		DELETE de

		FROM [dbo].[deductions] AS de

		WHERE de.[deduction_id] = @deduction_id
			AND de.[deduction_type] = @deduction_type
			AND de.[deduction_sub_type] = @deduction_sub_type
			AND de.[deduction_entity] = @deduction_entity;

		SET @log_message = CONCAT(N'Deleted by ', @changed_by, N' in Shiner Reports: ', STUFF(@description, 1, 16, N''), N'.');

		EXEC [dbo].[write_db_log]
			 @level = N'INFO'
			,@table = N'deductions'
			,@rows = 1
			,@action = N'delete deduction'
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
		,N'Deduction deleted.' AS [message];

END;

GO

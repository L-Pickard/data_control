USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [dbo].[delete_exclusion_rule]
	 @entity NVARCHAR(20)
	,@type NVARCHAR(20)
	,@table_name NVARCHAR(20)
	,@id NVARCHAR(20)
	,@brand_id NVARCHAR(20) = N''
	,@changed_by NVARCHAR(200)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Deletes one row of dbo.exclusions (its whole key is given) for the Shiner Reports portal, after saving a copy of the
rules as they are. dbo.sales stores its flags: run run_margin_rule_recalculation to update them.
Returns one row: outcome (ok or refused) and message.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @changed_by = LTRIM(RTRIM(ISNULL(@changed_by, N'')));

	IF @changed_by = N''
		THROW 50101, 'The @changed_by parameter cannot be blank.', 1;

	SET @entity = ISNULL(@entity, N'');
	SET @type = ISNULL(@type, N'');
	SET @table_name = ISNULL(@table_name, N'');
	SET @id = ISNULL(@id, N'');
	SET @brand_id = ISNULL(@brand_id, N'');

	DECLARE @refusal NVARCHAR(400);
	DECLARE @description NVARCHAR(400);
	DECLARE @log_message NVARCHAR(MAX);
	DECLARE @transaction_started BIT = 0;

	IF NOT EXISTS (
			SELECT 1

			FROM [dbo].[exclusions] AS ex

			WHERE ex.[rule_scope] = N'global' AND ex.[entity] = @entity
				AND ex.[type] = @type
				AND ex.[table_name] = @table_name
				AND ex.[id] = @id
				AND ex.[brand_id] = @brand_id
			)
		SET @refusal = N'That rule is no longer in the table.';
	ELSE IF APPLOCK_TEST(N'public', N'margin_rule_recalculation', N'Exclusive', N'Session') = 0
		SET @refusal = N'A recalculation is running. Try again when it has finished.';

	IF @refusal IS NOT NULL
	BEGIN
		SELECT N'refused' AS [outcome]
			,@refusal AS [message];

		RETURN;

	END;

	SET @description = CONCAT(N'Before deleting ', @type, N': ', @entity, N', ', @table_name, N' ', @id, CASE WHEN @brand_id <> N'' THEN CONCAT(N', brand ', @brand_id) ELSE N'' END);

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

		DELETE ex

		FROM [dbo].[exclusions] AS ex

		WHERE ex.[rule_scope] = N'global' AND ex.[entity] = @entity
			AND ex.[type] = @type
			AND ex.[table_name] = @table_name
			AND ex.[id] = @id
			AND ex.[brand_id] = @brand_id;

		SET @log_message = CONCAT(N'Deleted by ', @changed_by, N' in Shiner Reports: ', STUFF(@description, 1, 16, N''), N'.');

		EXEC [dbo].[write_db_log]
			 @level = N'INFO'
			,@table = N'exclusions'
			,@rows = 1
			,@action = N'delete exclusion or intercompany rule'
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
		,N'Rule deleted.' AS [message];

END;

GO

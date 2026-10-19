USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [dbo].[add_exclusion_rule]
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
Adds one row to dbo.exclusions for the Shiner Reports portal, after saving a copy of the rules as they are.

@type: exclusion or intercompany. @table_name: customers or vendors. @id: a customer_id or vendor_id that exists.
@brand_id: blank for the whole customer or vendor; a brand is allowed only on a customer exclusion (CK_exclusions_brand_scope).

sales_orders and purchase_orders work their flags out when read, so they follow at once. dbo.sales stores its flags:
run run_margin_rule_recalculation to update them. Returns one row: outcome (ok or refused) and message.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @changed_by = LTRIM(RTRIM(ISNULL(@changed_by, N'')));

	IF @changed_by = N''
		THROW 50101, 'The @changed_by parameter cannot be blank.', 1;

	SET @entity = LTRIM(RTRIM(ISNULL(@entity, N'')));
	SET @type = LOWER(LTRIM(RTRIM(ISNULL(@type, N''))));
	SET @table_name = LOWER(LTRIM(RTRIM(ISNULL(@table_name, N''))));
	SET @id = LTRIM(RTRIM(ISNULL(@id, N'')));
	SET @brand_id = LTRIM(RTRIM(ISNULL(@brand_id, N'')));

	DECLARE @refusal NVARCHAR(400);
	DECLARE @known_entity NVARCHAR(20);
	DECLARE @known_id NVARCHAR(20);
	DECLARE @known_brand NVARCHAR(20) = N'';
	DECLARE @name NVARCHAR(100);
	DECLARE @description NVARCHAR(400);
	DECLARE @log_message NVARCHAR(MAX);
	DECLARE @transaction_started BIT = 0;

	-- The stored values take the spelling of the tables they refer to, whatever was typed.

	SELECT @known_entity = en.[entity]

	FROM [dbo].[entities] AS en

	WHERE en.[entity] = @entity;

	IF @table_name = N'customers'
		SELECT @known_id = cu.[customer_id]
			,@name = cu.[customer_name]

		FROM [dbo].[customers] AS cu

		WHERE cu.[customer_id] = @id;

	IF @table_name = N'vendors'
		SELECT @known_id = ve.[vendor_id]
			,@name = ve.[vendor_name]

		FROM [dbo].[vendors] AS ve

		WHERE ve.[vendor_id] = @id;

	IF @brand_id <> N''
		SELECT @known_brand = br.[brand_id]

		FROM [dbo].[brands] AS br

		WHERE br.[brand_id] = @brand_id;

	IF @known_entity IS NULL
		SET @refusal = N'Choose a company from the list.';
	ELSE IF @type NOT IN (N'exclusion', N'intercompany')
		SET @refusal = N'Choose Exclusion or Intercompany.';
	ELSE IF @table_name NOT IN (N'customers', N'vendors')
		SET @refusal = N'Choose Customer or Vendor.';
	ELSE IF @id = N''
		OR @known_id IS NULL
		SET @refusal = CONCAT(N'There is no ', CASE @table_name WHEN N'customers' THEN N'customer' ELSE N'vendor' END, N' with that number.');
	ELSE IF @brand_id <> N''
		AND NOT (
			@type = N'exclusion'
			AND @table_name = N'customers'
			)
		SET @refusal = N'A brand can only be chosen for a customer exclusion.';
	ELSE IF @brand_id <> N''
		AND @known_brand = N''
		SET @refusal = N'Choose a brand from the list.';
	ELSE IF APPLOCK_TEST(N'public', N'margin_rule_recalculation', N'Exclusive', N'Session') = 0
		SET @refusal = N'A recalculation is running. Try again when it has finished.';
	ELSE IF EXISTS (
			SELECT 1

			FROM [dbo].[exclusions] AS ex

			WHERE ex.[entity] = @known_entity
				AND ex.[type] = @type
				AND ex.[table_name] = @table_name
				AND ex.[id] = @known_id
				AND ex.[brand_id] = @known_brand
			)
		SET @refusal = N'That rule is already in the table.';

	IF @refusal IS NOT NULL
	BEGIN
		SELECT N'refused' AS [outcome]
			,@refusal AS [message];

		RETURN;

	END;

	SET @description = CONCAT(N'Before adding ', @type, N': ', @known_entity, N', ', CASE @table_name WHEN N'customers' THEN N'customer ' ELSE N'vendor ' END, @known_id,
			N' ', ISNULL(@name, N''), CASE WHEN @known_brand <> N'' THEN CONCAT(N', brand ', @known_brand) ELSE N'' END);

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;

		END;

		EXEC [dbo].[save_margin_rule_snapshot]
			 @taken_by = @changed_by
			,@reason = N'add'
			,@description = @description
			,@return_row = 0;

		INSERT INTO [dbo].[exclusions] (
			 [entity]
			,[type]
			,[table_name]
			,[id]
			,[brand_id]
			)
		VALUES (
			 @known_entity
			,@type
			,@table_name
			,@known_id
			,@known_brand
			);

		SET @log_message = CONCAT(N'Added by ', @changed_by, N' in Shiner Reports: ', STUFF(@description, 1, 14, N''), N'.');

		EXEC [dbo].[write_db_log]
			 @level = N'INFO'
			,@table = N'exclusions'
			,@rows = 1
			,@action = N'add exclusion or intercompany rule'
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
		,N'Rule added.' AS [message];

END;

GO

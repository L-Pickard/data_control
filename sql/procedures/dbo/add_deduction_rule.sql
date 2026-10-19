USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [dbo].[add_deduction_rule]
	 @deduction_id NVARCHAR(20)
	,@deduction_type NVARCHAR(50)
	,@deduction_sub_type NVARCHAR(30) = N''
	,@deduction_entity NVARCHAR(20)
	,@deduction_value DECIMAL(38, 20)
	,@changed_by NVARCHAR(200)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Adds one row to dbo.deductions for the Shiner Reports portal, after saving a copy of the rules as they are. Only rows
the calculation functions can use are accepted:

Brand Royalty (fnc_calculate_item_royalty): @deduction_id is a brand; @deduction_sub_type is blank, or the three
characters at positions 5 to 7 of the item number (for example PCO). Shiner LLC uses the blank sub type only.

Customer Rebate (fnc_calculate_customer_rebate): @deduction_id is a customer; @deduction_sub_type is blank or a brand.
Shiner LLC takes no customer rebate, so a rebate cannot be added for it.

@deduction_value is a fraction of sales: 0.08 is 8%. It applies to new sales as they load; run
run_margin_rule_recalculation to apply it to sales already loaded. Returns one row: outcome (ok or refused) and message.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @changed_by = LTRIM(RTRIM(ISNULL(@changed_by, N'')));

	IF @changed_by = N''
		THROW 50101, 'The @changed_by parameter cannot be blank.', 1;

	SET @deduction_id = LTRIM(RTRIM(ISNULL(@deduction_id, N'')));
	SET @deduction_type = LTRIM(RTRIM(ISNULL(@deduction_type, N'')));
	SET @deduction_sub_type = UPPER(LTRIM(RTRIM(ISNULL(@deduction_sub_type, N''))));
	SET @deduction_entity = LTRIM(RTRIM(ISNULL(@deduction_entity, N'')));

	DECLARE @refusal NVARCHAR(400);
	DECLARE @known_entity NVARCHAR(20);
	DECLARE @known_type NVARCHAR(50);
	DECLARE @known_id NVARCHAR(20);
	DECLARE @known_sub_type NVARCHAR(30) = @deduction_sub_type;
	DECLARE @name NVARCHAR(100);
	DECLARE @description NVARCHAR(400);
	DECLARE @log_message NVARCHAR(MAX);
	DECLARE @transaction_started BIT = 0;

	SELECT @known_entity = en.[entity]

	FROM [dbo].[entities] AS en

	WHERE en.[entity] = @deduction_entity;

	SET @known_type = CASE @deduction_type
			WHEN N'Brand Royalty'
				THEN N'Brand Royalty'
			WHEN N'Customer Rebate'
				THEN N'Customer Rebate'
			END;

	IF @known_type = N'Brand Royalty'
		SELECT @known_id = br.[brand_id]
			,@name = br.[brand_name]

		FROM [dbo].[brands] AS br

		WHERE br.[brand_id] = @deduction_id;

	IF @known_type = N'Customer Rebate'
	BEGIN
		SELECT @known_id = cu.[customer_id]
			,@name = cu.[customer_name]

		FROM [dbo].[customers] AS cu

		WHERE cu.[customer_id] = @deduction_id;

		IF @deduction_sub_type <> N''
		BEGIN
			SET @known_sub_type = NULL;

			SELECT @known_sub_type = br.[brand_id]

			FROM [dbo].[brands] AS br

			WHERE br.[brand_id] = @deduction_sub_type;

		END;

	END;

	IF @known_entity IS NULL
		SET @refusal = N'Choose a company from the list.';
	ELSE IF @known_type IS NULL
		SET @refusal = N'Choose Brand Royalty or Customer Rebate.';
	ELSE IF @deduction_id = N''
		OR @known_id IS NULL
		SET @refusal = CASE @known_type
				WHEN N'Brand Royalty'
					THEN N'Choose a brand from the list.'
				ELSE N'There is no customer with that number.'
				END;
	ELSE IF @deduction_value IS NULL
		OR @deduction_value <= 0
		OR @deduction_value > 1
		SET @refusal = N'Enter a rate above 0% and up to 100%.';
	ELSE IF @known_type = N'Customer Rebate'
		AND @known_entity = N'Shiner LLC'
		SET @refusal = N'Shiner LLC takes no customer rebate, so a rebate for it would never be used.';
	ELSE IF @known_type = N'Customer Rebate'
		AND @known_sub_type IS NULL
		SET @refusal = N'Choose a brand from the list, or leave it as all brands.';
	ELSE IF @known_type = N'Brand Royalty'
		AND @known_entity = N'Shiner LLC'
		AND @deduction_sub_type <> N''
		SET @refusal = N'Shiner LLC royalties are by brand only, so an item type for it would never be used.';
	ELSE IF @known_type = N'Brand Royalty'
		AND @deduction_sub_type <> N''
		AND LEN(@deduction_sub_type) <> 3
		SET @refusal = N'An item type is the three characters at positions 5 to 7 of the item number, for example PCO.';
	ELSE IF APPLOCK_TEST(N'public', N'margin_rule_recalculation', N'Exclusive', N'Session') = 0
		SET @refusal = N'A recalculation is running. Try again when it has finished.';
	ELSE IF EXISTS (
			SELECT 1

			FROM [dbo].[deductions] AS de

			WHERE de.[deduction_id] = @known_id
				AND de.[deduction_type] = @known_type
				AND de.[deduction_sub_type] = @known_sub_type
				AND de.[deduction_entity] = @known_entity
			)
		SET @refusal = N'That deduction is already in the table. Delete it first to change its rate.';

	IF @refusal IS NOT NULL
	BEGIN
		SELECT N'refused' AS [outcome]
			,@refusal AS [message];

		RETURN;

	END;

	SET @description = CONCAT(N'Before adding ', @known_type, N': ', @known_entity, N', ', @known_id, N' ', ISNULL(@name, N''), CASE WHEN @known_sub_type <> N'' THEN CONCAT(N', ',
					@known_sub_type) ELSE N'' END, N', ', CAST(CAST(@deduction_value * 100 AS DECIMAL(9, 4)) AS NVARCHAR(20)), N'%');

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

		INSERT INTO [dbo].[deductions] (
			 [deduction_id]
			,[deduction_type]
			,[deduction_sub_type]
			,[deduction_entity]
			,[deduction_value]
			)
		VALUES (
			 @known_id
			,@known_type
			,@known_sub_type
			,@known_entity
			,@deduction_value
			);

		SET @log_message = CONCAT(N'Added by ', @changed_by, N' in Shiner Reports: ', STUFF(@description, 1, 14, N''), N'.');

		EXEC [dbo].[write_db_log]
			 @level = N'INFO'
			,@table = N'deductions'
			,@rows = 1
			,@action = N'add deduction'
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
		,N'Deduction added.' AS [message];

END;

GO

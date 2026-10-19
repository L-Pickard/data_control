USE [data_control];

GO

CREATE OR ALTER PROCEDURE [dbo].[update_dates_table]
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @transaction_started BIT = 0;

	IF OBJECT_ID(N'dbo.dates_staging', N'U') IS NULL
		THROW 50001, 'dbo.dates_staging does not exist.', 1;
	IF NOT EXISTS (SELECT 1 FROM [dbo].[dates_staging])
		THROW 50002, 'dbo.dates_staging contains no rows.', 1;
	IF EXISTS (
		SELECT [calendar_date]
		FROM [dbo].[dates_staging]
		GROUP BY [calendar_date]
		HAVING [calendar_date] IS NULL OR COUNT(*) > 1
	)
		THROW 50003, 'dbo.dates_staging contains a null or duplicate date.', 1;

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;
			SET @transaction_started = 1;
		END;

		UPDATE target
		SET  target.[is_placeholder] = 0
			,target.[day_of_month] = source.[day_of_month]
			,target.[day_of_week] = source.[day_of_week]
			,target.[day_of_year] = source.[day_of_year]
			,target.[day_name] = source.[day_name]
			,target.[day_name_abbreviation] = source.[day_name_abbreviation]
			,target.[week_of_year] = source.[week_of_year]
			,target.[week_of_month] = source.[week_of_month]
			,target.[calendar_year] = source.[calendar_year]
			,target.[calendar_month_no] = source.[calendar_month_no]
			,target.[calendar_month_year] = source.[calendar_month_year]
			,target.[calendar_year_month_no] = source.[calendar_year_month_no]
			,target.[calendar_month_start] = source.[calendar_month_start]
			,target.[calendar_month_end] = source.[calendar_month_end]
			,target.[calendar_quarter] = source.[calendar_quarter]
			,target.[calendar_quarter_name] = source.[calendar_quarter_name]
			,target.[calendar_quarter_start] = source.[calendar_quarter_start]
			,target.[calendar_quarter_end] = source.[calendar_quarter_end]
			,target.[iso_year] = source.[iso_year]
			,target.[iso_week_no] = source.[iso_week_no]
			,target.[iso_year_week] = source.[iso_year_week]
			,target.[financial_year_no] = source.[financial_year_no]
			,target.[financial_year_short] = source.[financial_year_short]
			,target.[financial_year_name] = source.[financial_year_name]
			,target.[financial_year_start] = source.[financial_year_start]
			,target.[financial_year_end] = source.[financial_year_end]
			,target.[financial_year_day_count] = source.[financial_year_day_count]
			,target.[day_of_financial_year] = source.[day_of_financial_year]
			,target.[days_remaining_in_financial_year] = source.[days_remaining_in_financial_year]
			,target.[financial_week_no] = source.[financial_week_no]
			,target.[financial_quarter] = source.[financial_quarter]
			,target.[financial_quarter_name] = source.[financial_quarter_name]
			,target.[financial_quarter_start] = source.[financial_quarter_start]
			,target.[financial_quarter_end] = source.[financial_quarter_end]
			,target.[day_of_financial_quarter] = source.[day_of_financial_quarter]
			,target.[financial_quarter_year] = source.[financial_quarter_year]
			,target.[financial_month_no] = source.[financial_month_no]
			,target.[financial_month_start] = source.[financial_month_start]
			,target.[financial_month_end] = source.[financial_month_end]
			,target.[day_of_financial_month] = source.[day_of_financial_month]
			,target.[month_name] = source.[month_name]
			,target.[month_name_abbreviation] = source.[month_name_abbreviation]
			,target.[month_abbreviation_year] = source.[month_abbreviation_year]
			,target.[month_financial_year] = source.[month_financial_year]
			,target.[financial_month_year_no] = source.[financial_month_year_no]
		FROM [dbo].[dates] AS target
		INNER JOIN [dbo].[dates_staging] AS source
			ON source.[calendar_date] = target.[calendar_date];

		INSERT INTO [dbo].[dates] (
			 [calendar_date], [is_placeholder], [day_of_month], [day_of_week]
			,[day_of_year], [day_name], [day_name_abbreviation], [week_of_year]
			,[week_of_month], [calendar_year], [calendar_month_no]
			,[calendar_month_year], [calendar_year_month_no], [calendar_month_start]
			,[calendar_month_end], [calendar_quarter], [calendar_quarter_name]
			,[calendar_quarter_start], [calendar_quarter_end], [iso_year]
			,[iso_week_no], [iso_year_week], [financial_year_no]
			,[financial_year_short], [financial_year_name], [financial_year_start]
			,[financial_year_end], [financial_year_day_count], [day_of_financial_year]
			,[days_remaining_in_financial_year], [financial_week_no]
			,[financial_quarter], [financial_quarter_name], [financial_quarter_start]
			,[financial_quarter_end], [day_of_financial_quarter]
			,[financial_quarter_year], [financial_month_no], [financial_month_start]
			,[financial_month_end], [day_of_financial_month], [month_name]
			,[month_name_abbreviation], [month_abbreviation_year]
			,[month_financial_year], [financial_month_year_no]
		)
		SELECT
			 source.[calendar_date], 0, source.[day_of_month], source.[day_of_week]
			,source.[day_of_year], source.[day_name], source.[day_name_abbreviation]
			,source.[week_of_year], source.[week_of_month], source.[calendar_year]
			,source.[calendar_month_no], source.[calendar_month_year]
			,source.[calendar_year_month_no], source.[calendar_month_start]
			,source.[calendar_month_end], source.[calendar_quarter]
			,source.[calendar_quarter_name], source.[calendar_quarter_start]
			,source.[calendar_quarter_end], source.[iso_year], source.[iso_week_no]
			,source.[iso_year_week], source.[financial_year_no]
			,source.[financial_year_short], source.[financial_year_name]
			,source.[financial_year_start], source.[financial_year_end]
			,source.[financial_year_day_count], source.[day_of_financial_year]
			,source.[days_remaining_in_financial_year], source.[financial_week_no]
			,source.[financial_quarter], source.[financial_quarter_name]
			,source.[financial_quarter_start], source.[financial_quarter_end]
			,source.[day_of_financial_quarter], source.[financial_quarter_year]
			,source.[financial_month_no], source.[financial_month_start]
			,source.[financial_month_end], source.[day_of_financial_month]
			,source.[month_name], source.[month_name_abbreviation]
			,source.[month_abbreviation_year], source.[month_financial_year]
			,source.[financial_month_year_no]
		FROM [dbo].[dates_staging] AS source
		WHERE NOT EXISTS (
			SELECT 1
			FROM [dbo].[dates] AS target
			WHERE target.[calendar_date] = source.[calendar_date]
		);

		IF NOT EXISTS (SELECT 1 FROM [dbo].[dates] WHERE [calendar_date] = '19000101')
			INSERT INTO [dbo].[dates] ([calendar_date], [is_placeholder])
			VALUES ('19000101', 1);
		IF NOT EXISTS (SELECT 1 FROM [dbo].[dates] WHERE [calendar_date] = '19010101')
			INSERT INTO [dbo].[dates] ([calendar_date], [is_placeholder])
			VALUES ('19010101', 1);

		DROP TABLE [dbo].[dates_staging];
		IF @transaction_started = 1
			COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF @transaction_started = 1 AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END;

GO

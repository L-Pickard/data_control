USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

IF OBJECT_ID(N'dbo.dates', N'U') IS NULL
BEGIN
	CREATE TABLE [dbo].[dates] (
		 [date_key] AS [dbo].[fnc_date_key]([calendar_date]) PERSISTED
		,[calendar_date] DATE NOT NULL
		,[is_placeholder] BIT NOT NULL CONSTRAINT [DF_dates_is_placeholder] DEFAULT (0)
		,[day_of_month] TINYINT NULL
		,[day_of_week] TINYINT NULL
		,[day_of_year] SMALLINT NULL
		,[day_name] NVARCHAR(9) NULL
		,[day_name_abbreviation] NCHAR(3) NULL
		,[week_of_year] TINYINT NULL
		,[week_of_month] TINYINT NULL
		,[calendar_year] SMALLINT NULL
		,[calendar_month_no] TINYINT NULL
		,[calendar_month_year] NVARCHAR(8) NULL
		,[calendar_year_month_no] INTEGER NULL
		,[calendar_month_start] DATE NULL
		,[calendar_month_end] DATE NULL
		,[calendar_quarter] TINYINT NULL
		,[calendar_quarter_name] NCHAR(2) NULL
		,[calendar_quarter_start] DATE NULL
		,[calendar_quarter_end] DATE NULL
		,[iso_year] SMALLINT NULL
		,[iso_week_no] TINYINT NULL
		,[iso_year_week] NCHAR(8) NULL
		,[financial_year_no] SMALLINT NULL
		,[financial_year_short] NCHAR(5) NULL
		,[financial_year_name] NVARCHAR(8) NULL
		,[financial_year_start] DATE NULL
		,[financial_year_end] DATE NULL
		,[financial_year_day_count] SMALLINT NULL
		,[day_of_financial_year] SMALLINT NULL
		,[days_remaining_in_financial_year] SMALLINT NULL
		,[financial_week_no] TINYINT NULL
		,[financial_quarter] TINYINT NULL
		,[financial_quarter_name] NCHAR(2) NULL
		,[financial_quarter_start] DATE NULL
		,[financial_quarter_end] DATE NULL
		,[day_of_financial_quarter] TINYINT NULL
		,[financial_quarter_year] NVARCHAR(8) NULL
		,[financial_month_no] TINYINT NULL
		,[financial_month_start] DATE NULL
		,[financial_month_end] DATE NULL
		,[day_of_financial_month] TINYINT NULL
		,[month_name] NVARCHAR(9) NULL
		,[month_name_abbreviation] NCHAR(3) NULL
		,[month_abbreviation_year] NCHAR(6) NULL
		,[month_financial_year] NVARCHAR(9) NULL
		,[financial_month_year_no] INTEGER NULL
		,CONSTRAINT [PK_dates] PRIMARY KEY CLUSTERED ([date_key])
		,CONSTRAINT [UQ_dates_calendar_date] UNIQUE ([calendar_date])
		,CONSTRAINT [CK_dates_day_of_week]
			CHECK ([day_of_week] IS NULL OR [day_of_week] BETWEEN 0 AND 6)
		,CONSTRAINT [CK_dates_calendar_month]
			CHECK ([calendar_month_no] IS NULL OR [calendar_month_no] BETWEEN 1 AND 12)
		,CONSTRAINT [CK_dates_calendar_quarter]
			CHECK ([calendar_quarter] IS NULL OR [calendar_quarter] BETWEEN 1 AND 4)
		,CONSTRAINT [CK_dates_financial_month]
			CHECK ([financial_month_no] IS NULL OR [financial_month_no] BETWEEN 1 AND 12)
		,CONSTRAINT [CK_dates_financial_quarter]
			CHECK ([financial_quarter] IS NULL OR [financial_quarter] BETWEEN 1 AND 4)
		,CONSTRAINT [CK_dates_placeholder_attributes]
			CHECK (
				[is_placeholder] = 0
				OR (
					[day_of_month] IS NULL
					AND [financial_year_no] IS NULL
				)
			)
	);

	CREATE NONCLUSTERED INDEX [IX_dates_calendar_period]
		ON [dbo].[dates] ([calendar_year], [calendar_month_no], [calendar_date]);

	CREATE NONCLUSTERED INDEX [IX_dates_financial_period]
		ON [dbo].[dates] (
			 [financial_year_no]
			,[financial_quarter]
			,[financial_month_no]
			,[calendar_date]
		);
END;

GO

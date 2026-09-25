-- Self-contained deployment; validates existing data and view column positions before commit.
USE [data_control];
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;
BEGIN TRY
    BEGIN TRANSACTION;
    IF COL_LENGTH('dbo.dates', 'iso_week_start') IS NOT NULL
        THROW 51000, 'iso_week_start already exists; inspect before rerunning.', 1;
    SELECT * INTO #dates_before FROM dbo.dates;
    SELECT * INTO #catalogue_before FROM dbo.date_catalogue;
    SELECT column_id, name INTO #catalogue_columns
    FROM sys.columns WHERE object_id = OBJECT_ID('dbo.date_catalogue');

    ALTER TABLE dbo.dates ADD [iso_week_start] AS (CASE WHEN [is_placeholder] = 0 THEN DATEADD(DAY, -((DATEDIFF(DAY, CONVERT(DATE, '19000101', 112), [calendar_date]) % 7 + 7) % 7), [calendar_date]) END);
    EXEC sys.sp_executesql N'CREATE OR ALTER VIEW [dbo].[date_catalogue]
AS
WITH current_period AS (
	SELECT today.[calendar_date]
		,today.[iso_year]
		,today.[iso_week_no]
		,today.[calendar_year]
		,today.[calendar_month_no]
		,today.[financial_month_start]
		,today.[financial_month_end]
		,today.[financial_quarter_start]
		,today.[financial_quarter_end]
		,today.[financial_year_start]
		,today.[financial_year_end]
		,previous_month.[financial_month_start] AS [previous_financial_month_start]
		,previous_month.[financial_month_end] AS [previous_financial_month_end]
		,previous_quarter.[financial_quarter_start] AS [previous_financial_quarter_start]
		,previous_quarter.[financial_quarter_end] AS [previous_financial_quarter_end]
		,previous_year.[financial_year_start] AS [previous_financial_year_start]
		,previous_year.[financial_year_end] AS [previous_financial_year_end]
		,rolling_start.[financial_month_start] AS [rolling_12_month_start]
	FROM [dbo].[dates] AS today
	LEFT JOIN [dbo].[dates] AS previous_month
		ON previous_month.[calendar_date] = DATEADD(DAY, -1, today.[financial_month_start])
	LEFT JOIN [dbo].[dates] AS previous_quarter
		ON previous_quarter.[calendar_date] = DATEADD(DAY, -1, today.[financial_quarter_start])
	LEFT JOIN [dbo].[dates] AS previous_year
		ON previous_year.[calendar_date] = DATEADD(DAY, -1, today.[financial_year_start])
	LEFT JOIN [dbo].[dates] AS rolling_start
		-- Anchor on the financial month''s end: 30 April belongs to May.
		ON rolling_start.[calendar_date] = DATEADD(MONTH, -11, today.[financial_month_end])
	WHERE today.[calendar_date] = CONVERT(DATE, SYSDATETIME())
)
SELECT dates.[date_key]
	,dates.[calendar_date]
	,dates.[is_placeholder]
	,dates.[day_of_month]
	,dates.[day_of_week]
	,dates.[day_of_year]
	,dates.[day_name]
	,dates.[day_name_abbreviation]
	,dates.[week_of_year]
	,dates.[week_of_month]
	,dates.[calendar_year]
	,dates.[calendar_month_no]
	,dates.[calendar_month_year]
	,dates.[calendar_year_month_no]
	,dates.[calendar_month_start]
	,dates.[calendar_month_end]
	,dates.[calendar_quarter]
	,dates.[calendar_quarter_name]
	,dates.[calendar_quarter_start]
	,dates.[calendar_quarter_end]
	,dates.[iso_year]
	,dates.[iso_week_no]
	,dates.[iso_year_week]
	,dates.[financial_year_no]
	,dates.[financial_year_short]
	,dates.[financial_year_name]
	,dates.[financial_year_start]
	,dates.[financial_year_end]
	,dates.[financial_year_day_count]
	,dates.[day_of_financial_year]
	,dates.[days_remaining_in_financial_year]
	,dates.[financial_week_no]
	,dates.[financial_quarter]
	,dates.[financial_quarter_name]
	,dates.[financial_quarter_start]
	,dates.[financial_quarter_end]
	,dates.[day_of_financial_quarter]
	,dates.[financial_quarter_year]
	,dates.[financial_month_no]
	,dates.[financial_month_start]
	,dates.[financial_month_end]
	,dates.[day_of_financial_month]
	,dates.[month_name]
	,dates.[month_name_abbreviation]
	,dates.[month_abbreviation_year]
	,dates.[month_financial_year]
	,dates.[financial_month_year_no]
	,CAST(CASE WHEN dates.[calendar_date] = current_period.[calendar_date] THEN 1 ELSE 0 END AS BIT) AS [is_today]
	,CAST(CASE WHEN dates.[calendar_date] = DATEADD(DAY, -1, current_period.[calendar_date]) THEN 1 ELSE 0 END AS BIT) AS [is_yesterday]
	,CAST(CASE
		WHEN dates.[iso_year] = current_period.[iso_year]
			AND dates.[iso_week_no] = current_period.[iso_week_no] THEN 1
		ELSE 0
	END AS BIT) AS [is_current_week]
	,CAST(CASE
		WHEN dates.[calendar_year] = current_period.[calendar_year]
			AND dates.[calendar_month_no] = current_period.[calendar_month_no] THEN 1
		ELSE 0
	END AS BIT) AS [is_current_month]
	,CAST(CASE WHEN dates.[financial_month_start] = current_period.[financial_month_start] THEN 1 ELSE 0 END AS BIT) AS [is_current_financial_month]
	,CAST(CASE WHEN dates.[financial_quarter_start] = current_period.[financial_quarter_start] THEN 1 ELSE 0 END AS BIT) AS [is_current_financial_quarter]
	,CAST(CASE WHEN dates.[financial_year_start] = current_period.[financial_year_start] THEN 1 ELSE 0 END AS BIT) AS [is_current_financial_year]
	,CAST(CASE WHEN dates.[financial_year_start] = current_period.[previous_financial_year_start] THEN 1 ELSE 0 END AS BIT) AS [is_previous_financial_year]
	,CAST(CASE
		WHEN dates.[calendar_date] BETWEEN current_period.[financial_month_start]
			AND current_period.[calendar_date] THEN 1 ELSE 0
	END AS BIT) AS [is_financial_month_to_date]
	,CAST(CASE
		WHEN dates.[calendar_date] BETWEEN current_period.[financial_quarter_start]
			AND current_period.[calendar_date] THEN 1 ELSE 0
	END AS BIT) AS [is_financial_quarter_to_date]
	,CAST(CASE
		WHEN dates.[calendar_date] BETWEEN current_period.[financial_year_start]
			AND current_period.[calendar_date] THEN 1 ELSE 0
	END AS BIT) AS [is_financial_year_to_date]
	,CAST(CASE
		WHEN dates.[calendar_date] BETWEEN current_period.[previous_financial_month_start]
			AND current_period.[previous_financial_month_end] THEN 1 ELSE 0
	END AS BIT) AS [is_last_financial_month]
	,CAST(CASE
		WHEN dates.[calendar_date] BETWEEN current_period.[previous_financial_quarter_start]
			AND current_period.[previous_financial_quarter_end] THEN 1 ELSE 0
	END AS BIT) AS [is_last_financial_quarter]
	,CAST(CASE
		WHEN dates.[calendar_date] BETWEEN current_period.[previous_financial_year_start]
			AND current_period.[previous_financial_year_end] THEN 1 ELSE 0
	END AS BIT) AS [is_last_financial_year]
	,CAST(CASE
		WHEN dates.[calendar_date] BETWEEN current_period.[rolling_12_month_start]
			AND current_period.[financial_month_end] THEN 1 ELSE 0
	END AS BIT) AS [is_rolling_12_financial_months]
	,dates.[iso_week_start]
FROM [dbo].[dates] AS dates
CROSS JOIN current_period
WHERE dates.[is_placeholder] = 0;';

    EXEC sys.sp_executesql N'
        IF EXISTS (
            SELECT 1 FROM dbo.dates
            WHERE (is_placeholder = 1 AND iso_week_start IS NOT NULL)
               OR (is_placeholder = 0 AND (
                   iso_week_start IS NULL
                   OR iso_week_start <> DATEADD(DAY, -CONVERT(INT, day_of_week), calendar_date)
                   OR DATEDIFF(DAY, iso_week_start, calendar_date) NOT BETWEEN 0 AND 6
                   OR DATEPART(ISO_WEEK, iso_week_start) <> iso_week_no
                   OR YEAR(DATEADD(DAY, 3, iso_week_start)) <> iso_year))
        ) THROW 51000, ''ISO week start validation failed.'', 1;
        IF EXISTS (
            SELECT 1 FROM dbo.date_catalogue v JOIN dbo.dates d ON d.date_key = v.date_key
            WHERE v.iso_week_start IS NULL OR v.iso_week_start <> d.iso_week_start
        ) THROW 51000, ''Catalogue week start validation failed.'', 1;
    ';
    DECLARE @columns NVARCHAR(MAX), @sql NVARCHAR(MAX);
    SELECT @columns = STRING_AGG(CONVERT(NVARCHAR(MAX), QUOTENAME(name)), ',') WITHIN GROUP (ORDER BY column_id)
    FROM tempdb.sys.columns WHERE object_id = OBJECT_ID('tempdb..#dates_before');
    SET @sql = N'IF EXISTS (SELECT ' + @columns + N' FROM dbo.dates EXCEPT SELECT * FROM #dates_before)
        OR EXISTS (SELECT * FROM #dates_before EXCEPT SELECT ' + @columns + N' FROM dbo.dates)
        THROW 51000, ''Existing date values changed.'', 1;';
    EXEC sys.sp_executesql @sql;
    SELECT @columns = STRING_AGG(CONVERT(NVARCHAR(MAX), QUOTENAME(name)), ',') WITHIN GROUP (ORDER BY column_id)
    FROM #catalogue_columns;
    SET @sql = N'IF EXISTS (SELECT ' + @columns + N' FROM dbo.date_catalogue EXCEPT SELECT * FROM #catalogue_before)
        OR EXISTS (SELECT * FROM #catalogue_before EXCEPT SELECT ' + @columns + N' FROM dbo.date_catalogue)
        THROW 51000, ''Existing catalogue values changed.'', 1;';
    EXEC sys.sp_executesql @sql;
    IF EXISTS (SELECT column_id, name FROM #catalogue_columns EXCEPT
        SELECT column_id, name FROM sys.columns WHERE object_id = OBJECT_ID('dbo.date_catalogue'))
        THROW 51000, 'Existing catalogue column positions changed.', 1;
    IF (SELECT COUNT(*) FROM dbo.dates) <> (SELECT COUNT(*) FROM #dates_before)
       OR (SELECT COUNT(*) FROM dbo.date_catalogue) <> (SELECT COUNT(*) FROM #catalogue_before)
        THROW 51000, 'Row counts changed.', 1;
    COMMIT TRANSACTION;
    SELECT 'PASS: ISO week start deployed; existing values, row counts and view column positions preserved' AS result;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
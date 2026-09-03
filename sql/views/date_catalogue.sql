USE [data_control];

GO

CREATE OR ALTER VIEW [dbo].[date_catalogue]
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
		ON rolling_start.[calendar_date] = DATEADD(MONTH, -11, today.[calendar_date])
	WHERE today.[calendar_date] = CONVERT(DATE, SYSDATETIME())
)
SELECT dates.*
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
FROM [dbo].[dates] AS dates
CROSS JOIN current_period
WHERE dates.[is_placeholder] = 0;

GO

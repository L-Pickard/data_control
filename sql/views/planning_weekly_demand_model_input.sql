USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO


CREATE OR ALTER VIEW [planning].[weekly_demand_model_input]
AS

/*
    Complete weekly demand history for forecasting.

    A series begins in its first observed sales week. It then receives one row
    per calendar week through the latest observed week for its planning entity.
    Weeks without a row in weekly_demand_actuals are represented explicitly as
    zero demand.

    Weeks before a series first sells are intentionally omitted. A zero after
    the last observed sale is retained and identified by is_after_last_sales_week
    so product dormancy can be handled explicitly by the forecasting pipeline.
*/

WITH series_boundaries_base AS (
    SELECT
         a.[planning_entity]
        ,a.[brand_id]
        ,a.[category_code]
        ,a.[group_code]
        ,MIN(a.[week_start]) AS [series_first_sales_week]
        ,MAX(a.[week_start]) AS [series_last_sales_week]
    FROM [planning].[weekly_demand_actuals] AS a
    GROUP BY
         a.[planning_entity]
        ,a.[brand_id]
        ,a.[category_code]
        ,a.[group_code]
),
series_boundaries AS (
    SELECT
         [planning_entity]
        ,[brand_id]
        ,[category_code]
        ,[group_code]
        ,[series_first_sales_week]
        ,[series_last_sales_week]
        ,MAX([series_last_sales_week]) OVER (
            PARTITION BY [planning_entity]
         ) AS [planning_entity_latest_week]
    FROM series_boundaries_base
),
calendar_weeks AS (
    SELECT DISTINCT
        DATEADD(
             DAY
            ,-(DATEDIFF(DAY, CONVERT(DATE, '19000101', 112), d.[calendar_date]) % 7)
            ,d.[calendar_date]
        ) AS [week_start]
    FROM [dbo].[dates] AS d
),
series_calendar AS (
    SELECT
         w.[week_start]
        ,s.[planning_entity]
        ,s.[brand_id]
        ,s.[category_code]
        ,s.[group_code]
        ,s.[series_first_sales_week]
        ,s.[series_last_sales_week]
        ,s.[planning_entity_latest_week]
    FROM series_boundaries AS s
    INNER JOIN calendar_weeks AS w
        ON w.[week_start] BETWEEN s.[series_first_sales_week] AND s.[planning_entity_latest_week]
)
SELECT
     c.[week_start]
    ,c.[planning_entity]
    ,c.[brand_id]
    ,c.[category_code]
    ,c.[group_code]
    ,c.[series_first_sales_week]
    ,c.[series_last_sales_week]
    ,c.[planning_entity_latest_week]
    ,CAST(CASE WHEN a.[week_start] IS NULL THEN 0 ELSE 1 END AS BIT) AS [has_observed_activity]
    ,CAST(CASE WHEN a.[week_start] IS NULL THEN 1 ELSE 0 END AS BIT) AS [is_zero_filled]
    ,CAST(CASE WHEN c.[week_start] > c.[series_last_sales_week] THEN 1 ELSE 0 END AS BIT) AS [is_after_last_sales_week]
    ,COALESCE(a.[net_units], CONVERT(DECIMAL(38, 20), 0)) AS [net_units]
    ,COALESCE(a.[gross_units], CONVERT(DECIMAL(38, 20), 0)) AS [gross_units]
    ,COALESCE(a.[return_units], CONVERT(DECIMAL(38, 20), 0)) AS [return_units]
    ,COALESCE(a.[gbp_sales], CONVERT(DECIMAL(38, 20), 0)) AS [gbp_sales]
    ,COALESCE(a.[gbp_adjusted_margin], CONVERT(DECIMAL(38, 20), 0)) AS [gbp_adjusted_margin]
    ,COALESCE(a.[sales_line_count], CONVERT(BIGINT, 0)) AS [sales_line_count]
    ,COALESCE(a.[customer_count], 0) AS [customer_count]
    ,COALESCE(a.[item_count], 0) AS [item_count]
FROM series_calendar AS c
LEFT JOIN [planning].[weekly_demand_actuals] AS a
    ON a.[week_start] = c.[week_start]
   AND a.[planning_entity] = c.[planning_entity]
   AND a.[brand_id] = c.[brand_id]
   AND a.[category_code] = c.[category_code]
   AND a.[group_code] = c.[group_code];

GO

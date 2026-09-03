USE [data_control];

SET NOCOUNT ON;

/*
    Demand forecasting - Step 1 diagnostic

    Purpose
      * Map legal entities to operational planning entities.
      * Exclude intercompany and reporting-excluded sales.
      * Aggregate net external unit demand by week and product hierarchy.
      * Assess whether leaf-level series have enough history for direct forecasting.

    This script is read-only. It creates temporary tables only.
*/

DECLARE @minimum_history_weeks INTEGER = 26;
DECLARE @minimum_active_weeks INTEGER = 13;

DROP TABLE IF EXISTS #weekly_external_demand;
DROP TABLE IF EXISTS #series_diagnostic;

WITH external_sales AS (
    SELECT
         DATEADD(DAY, -(DATEDIFF(DAY, CONVERT(DATE, '19000101', 112), s.[posting_date]) % 7), s.[posting_date]) AS [week_start]
        ,CASE
            WHEN s.[entity] IN (N'Example Ltd', N'Example BV') THEN N'UK_EU'
            WHEN s.[entity] = N'Example LLC' THEN N'US'
         END AS [planning_entity]
        ,COALESCE(NULLIF(LTRIM(RTRIM(i.[brand_id])), N''), N'UNKNOWN_BRAND') AS [brand_id]
        ,COALESCE(NULLIF(LTRIM(RTRIM(i.[category_code])), N''), N'UNKNOWN_CATEGORY') AS [category_code]
        ,COALESCE(NULLIF(LTRIM(RTRIM(i.[group_code])), N''), N'UNKNOWN_GROUP') AS [group_code]
        ,s.[customer_id]
        ,s.[quantity]
        ,s.[gbp_sales]
        ,s.[gbp_adjusted_margin]
    FROM [dbo].[sales] AS s
    LEFT JOIN [dbo].[items] AS i
        ON i.[item_id] = s.[item_id]
    WHERE s.[intercompany] = 0
      AND s.[exclusion] = 0
      AND s.[entity] IN (N'Example Ltd', N'Example BV', N'Example LLC')
)
SELECT
     [week_start]
    ,[planning_entity]
    ,[brand_id]
    ,[category_code]
    ,[group_code]
    ,SUM([quantity]) AS [net_units]
    ,SUM([gbp_sales]) AS [gbp_sales]
    ,SUM([gbp_adjusted_margin]) AS [gbp_adjusted_margin]
    ,COUNT_BIG(*) AS [sales_line_count]
    ,COUNT(DISTINCT [customer_id]) AS [customer_count]
INTO #weekly_external_demand
FROM external_sales
GROUP BY
     [week_start]
    ,[planning_entity]
    ,[brand_id]
    ,[category_code]
    ,[group_code];

SELECT
     [planning_entity]
    ,[brand_id]
    ,[category_code]
    ,[group_code]
    ,MIN([week_start]) AS [first_sales_week]
    ,MAX([week_start]) AS [last_sales_week]
    ,DATEDIFF(WEEK, MIN([week_start]), MAX([week_start])) + 1 AS [history_weeks]
    ,COUNT_BIG(*) AS [active_weeks]
    ,SUM([net_units]) AS [net_units]
    ,SUM([gbp_sales]) AS [gbp_sales]
    ,SUM([gbp_adjusted_margin]) AS [gbp_adjusted_margin]
    ,SUM([sales_line_count]) AS [sales_line_count]
    ,CASE
        WHEN DATEDIFF(WEEK, MIN([week_start]), MAX([week_start])) + 1 < @minimum_history_weeks
            THEN N'PARENT_FALLBACK_SHORT_HISTORY'
        WHEN COUNT_BIG(*) < @minimum_active_weeks
            THEN N'PARENT_FALLBACK_SPARSE'
        ELSE N'DIRECT_LEAF_FORECAST'
     END AS [forecast_strategy]
INTO #series_diagnostic
FROM #weekly_external_demand
GROUP BY
     [planning_entity]
    ,[brand_id]
    ,[category_code]
    ,[group_code];

-- Result 1: audit the entity mapping and exclusions before modelling.
SELECT
     CASE
        WHEN [entity] IN (N'Example Ltd', N'Example BV') THEN N'UK_EU'
        WHEN [entity] = N'Example LLC' THEN N'US'
        ELSE N'UNMAPPED'
     END AS [planning_entity]
    ,[entity] AS [source_entity]
    ,COUNT_BIG(*) AS [all_sales_lines]
    ,SUM(CASE WHEN [intercompany] = 1 THEN 1 ELSE 0 END) AS [intercompany_lines_excluded]
    ,SUM(CASE WHEN [exclusion] = 1 THEN 1 ELSE 0 END) AS [reporting_exclusion_lines_excluded]
    ,SUM(CASE WHEN [intercompany] = 0 AND [exclusion] = 0 THEN 1 ELSE 0 END) AS [external_sales_lines_retained]
    ,SUM(CASE WHEN [intercompany] = 0 AND [exclusion] = 0 THEN [quantity] ELSE 0 END) AS [external_net_units_retained]
FROM [dbo].[sales]
GROUP BY
     CASE
        WHEN [entity] IN (N'Example Ltd', N'Example BV') THEN N'UK_EU'
        WHEN [entity] = N'Example LLC' THEN N'US'
        ELSE N'UNMAPPED'
     END
    ,[entity]
ORDER BY [planning_entity], [source_entity];

-- Result 2: readiness summary for the proposed leaf-level series.
SELECT
     [planning_entity]
    ,[forecast_strategy]
    ,COUNT_BIG(*) AS [series_count]
    ,SUM([net_units]) AS [net_units]
    ,SUM([gbp_sales]) AS [gbp_sales]
    ,MIN([history_weeks]) AS [minimum_history_weeks]
    ,MAX([history_weeks]) AS [maximum_history_weeks]
FROM #series_diagnostic
GROUP BY [planning_entity], [forecast_strategy]
ORDER BY [planning_entity], [forecast_strategy];

-- Result 3: hierarchy completeness in the retained sales population.
SELECT
     [planning_entity]
    ,SUM(CASE WHEN [brand_id] = N'UNKNOWN_BRAND' THEN [sales_line_count] ELSE 0 END) AS [unknown_brand_lines]
    ,SUM(CASE WHEN [category_code] = N'UNKNOWN_CATEGORY' THEN [sales_line_count] ELSE 0 END) AS [unknown_category_lines]
    ,SUM(CASE WHEN [group_code] = N'UNKNOWN_GROUP' THEN [sales_line_count] ELSE 0 END) AS [unknown_group_lines]
    ,SUM([sales_line_count]) AS [total_retained_lines]
FROM #weekly_external_demand
GROUP BY [planning_entity]
ORDER BY [planning_entity];

-- Result 4: the 200 largest leaf series for detailed review.
SELECT TOP (200)
     [planning_entity]
    ,[brand_id]
    ,[category_code]
    ,[group_code]
    ,[first_sales_week]
    ,[last_sales_week]
    ,[history_weeks]
    ,[active_weeks]
    ,CAST(100.0 * [active_weeks] / NULLIF([history_weeks], 0) AS DECIMAL(6, 2)) AS [active_week_percentage]
    ,[net_units]
    ,[gbp_sales]
    ,[gbp_adjusted_margin]
    ,[forecast_strategy]
FROM #series_diagnostic
ORDER BY ABS([net_units]) DESC;

-- Result 5: recent weekly demand sample, suitable for charting and spot checks.
SELECT
     [week_start]
    ,[planning_entity]
    ,[brand_id]
    ,[category_code]
    ,[group_code]
    ,[net_units]
    ,[gbp_sales]
    ,[gbp_adjusted_margin]
    ,[sales_line_count]
    ,[customer_count]
FROM #weekly_external_demand
WHERE [week_start] >= DATEADD(WEEK, -12, (SELECT MAX([week_start]) FROM #weekly_external_demand))
ORDER BY
     [week_start]
    ,[planning_entity]
    ,[brand_id]
    ,[category_code]
    ,[group_code];

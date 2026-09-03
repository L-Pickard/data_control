USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO


CREATE OR ALTER VIEW [planning].[weekly_demand_baseline_backtest]
AS

/*
    Rolling-origin backtest for simple weekly demand baselines.

    Each forecast uses only demand known on or before forecast_origin_week.
    Forecasts are evaluated from 1 through 12 weeks ahead. Negative baseline
    forecasts are floored at zero because planned unit demand cannot be negative.
*/

WITH origin_features AS (
    SELECT
         m.[week_start] AS [forecast_origin_week]
        ,m.[planning_entity]
        ,m.[brand_id]
        ,m.[category_code]
        ,m.[group_code]
        ,m.[weeks_since_series_start]
        ,m.[net_units] AS [last_week_forecast]
        ,AVG(m.[net_units]) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
         ) AS [average_4_week_forecast]
        ,AVG(m.[net_units]) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
            ROWS BETWEEN 12 PRECEDING AND CURRENT ROW
         ) AS [average_13_week_forecast]
    FROM [planning].[weekly_demand_features] AS m
),
forecast_targets AS (
    SELECT
         o.[forecast_origin_week]
        ,DATEADD(WEEK, h.[forecast_horizon_weeks], o.[forecast_origin_week]) AS [target_week]
        ,h.[forecast_horizon_weeks]
        ,o.[planning_entity]
        ,o.[brand_id]
        ,o.[category_code]
        ,o.[group_code]
        ,o.[weeks_since_series_start]
        ,o.[last_week_forecast]
        ,o.[average_4_week_forecast]
        ,o.[average_13_week_forecast]
    FROM origin_features AS o
    CROSS JOIN (
        VALUES (1), (2), (3), (4), (5), (6),
               (7), (8), (9), (10), (11), (12)
    ) AS h ([forecast_horizon_weeks])
),
forecasts_with_actuals AS (
    SELECT
         f.[forecast_origin_week]
        ,f.[target_week]
        ,f.[forecast_horizon_weeks]
        ,f.[planning_entity]
        ,f.[brand_id]
        ,f.[category_code]
        ,f.[group_code]
        ,a.[net_units] AS [actual_net_units]
        ,f.[last_week_forecast]
        ,CASE
            WHEN f.[weeks_since_series_start] >= 3
                THEN f.[average_4_week_forecast]
         END AS [average_4_week_forecast]
        ,CASE
            WHEN f.[weeks_since_series_start] >= 12
                THEN f.[average_13_week_forecast]
         END AS [average_13_week_forecast]
        ,s.[net_units] AS [seasonal_52_week_forecast]
    FROM forecast_targets AS f
    INNER JOIN [planning].[weekly_demand_model_input] AS a
        ON a.[week_start] = f.[target_week]
       AND a.[planning_entity] = f.[planning_entity]
       AND a.[brand_id] = f.[brand_id]
       AND a.[category_code] = f.[category_code]
       AND a.[group_code] = f.[group_code]
    LEFT JOIN [planning].[weekly_demand_model_input] AS s
        ON s.[week_start] = DATEADD(WEEK, -52, f.[target_week])
       AND s.[planning_entity] = f.[planning_entity]
       AND s.[brand_id] = f.[brand_id]
       AND s.[category_code] = f.[category_code]
       AND s.[group_code] = f.[group_code]
),
long_forecasts AS (
    SELECT
         f.[forecast_origin_week]
        ,f.[target_week]
        ,f.[forecast_horizon_weeks]
        ,f.[planning_entity]
        ,f.[brand_id]
        ,f.[category_code]
        ,f.[group_code]
        ,f.[actual_net_units]
        ,b.[baseline_method]
        ,CASE
            WHEN b.[raw_forecast_units] < 0 THEN CONVERT(DECIMAL(38, 20), 0)
            ELSE b.[raw_forecast_units]
         END AS [forecast_net_units]
    FROM forecasts_with_actuals AS f
    CROSS APPLY (
        VALUES
             (N'LAST_WEEK', f.[last_week_forecast])
            ,(N'AVERAGE_4_WEEKS', f.[average_4_week_forecast])
            ,(N'AVERAGE_13_WEEKS', f.[average_13_week_forecast])
            ,(N'SEASONAL_52_WEEKS', f.[seasonal_52_week_forecast])
    ) AS b ([baseline_method], [raw_forecast_units])
    WHERE b.[raw_forecast_units] IS NOT NULL
)
SELECT
     [forecast_origin_week]
    ,[target_week]
    ,[forecast_horizon_weeks]
    ,[planning_entity]
    ,[brand_id]
    ,[category_code]
    ,[group_code]
    ,[baseline_method]
    ,[actual_net_units]
    ,[forecast_net_units]
    ,[forecast_net_units] - [actual_net_units] AS [error_units]
    ,ABS([forecast_net_units] - [actual_net_units]) AS [absolute_error_units]
FROM long_forecasts;

GO

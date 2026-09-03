USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO


CREATE OR ALTER VIEW [planning].[weekly_demand_features]
AS

/*
    Leakage-safe historical features for weekly demand forecasting.

    Every lag and rolling feature uses rows strictly before the feature row's
    week_start. Current-week demand remains present as the eventual training
    target, but is never included in its own predictive features.
*/

WITH historical_features AS (
    SELECT
         m.*
        ,LAG(m.[net_units], 1) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
         ) AS [net_units_lag_1_week]
        ,LAG(m.[net_units], 2) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
         ) AS [net_units_lag_2_weeks]
        ,LAG(m.[net_units], 4) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
         ) AS [net_units_lag_4_weeks]
        ,LAG(m.[net_units], 13) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
         ) AS [net_units_lag_13_weeks]
        ,LAG(m.[net_units], 26) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
         ) AS [net_units_lag_26_weeks]
        ,LAG(m.[net_units], 52) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
         ) AS [net_units_lag_52_weeks]
        ,AVG(m.[net_units]) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
            ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING
         ) AS [net_units_average_previous_4_weeks]
        ,AVG(m.[net_units]) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
            ROWS BETWEEN 8 PRECEDING AND 1 PRECEDING
         ) AS [net_units_average_previous_8_weeks]
        ,AVG(m.[net_units]) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
            ROWS BETWEEN 13 PRECEDING AND 1 PRECEDING
         ) AS [net_units_average_previous_13_weeks]
        ,AVG(m.[net_units]) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
            ROWS BETWEEN 26 PRECEDING AND 1 PRECEDING
         ) AS [net_units_average_previous_26_weeks]
        ,STDEV(m.[net_units]) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
            ROWS BETWEEN 13 PRECEDING AND 1 PRECEDING
         ) AS [net_units_stdev_previous_13_weeks]
        ,AVG(CONVERT(DECIMAL(9, 8), m.[has_observed_activity])) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
            ROWS BETWEEN 13 PRECEDING AND 1 PRECEDING
         ) AS [activity_rate_previous_13_weeks]
        ,AVG(m.[net_units]) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
            ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING
         ) - AVG(m.[net_units]) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
            ROWS BETWEEN 8 PRECEDING AND 5 PRECEDING
         ) AS [net_units_recent_4_week_trend]
        ,MAX(CASE WHEN m.[has_observed_activity] = 1 THEN m.[week_start] END) OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
         ) AS [previous_activity_week]
        ,ROW_NUMBER() OVER (
            PARTITION BY m.[planning_entity], m.[brand_id], m.[category_code], m.[group_code]
            ORDER BY m.[week_start]
         ) - 1 AS [weeks_since_series_start]
    FROM [planning].[weekly_demand_model_input] AS m
)
SELECT
     f.*
    ,DATEDIFF(WEEK, f.[previous_activity_week], f.[week_start]) AS [weeks_since_previous_activity]
    ,CAST(CASE WHEN f.[weeks_since_series_start] >= 4 THEN 1 ELSE 0 END AS BIT) AS [has_4_weeks_history]
    ,CAST(CASE WHEN f.[weeks_since_series_start] >= 13 THEN 1 ELSE 0 END AS BIT) AS [has_13_weeks_history]
    ,CAST(CASE WHEN f.[weeks_since_series_start] >= 26 THEN 1 ELSE 0 END AS BIT) AS [has_26_weeks_history]
    ,CAST(CASE WHEN f.[weeks_since_series_start] >= 52 THEN 1 ELSE 0 END AS BIT) AS [has_52_weeks_history]
    ,d.[iso_year]
    ,d.[iso_week_no]
    ,d.[iso_year_week]
    ,d.[calendar_year]
    ,d.[calendar_month_no]
    ,d.[calendar_quarter]
    ,d.[financial_year_no]
    ,d.[financial_week_no]
    ,d.[financial_month_no]
    ,d.[financial_quarter]
FROM historical_features AS f
LEFT JOIN [dbo].[dates] AS d
    ON d.[calendar_date] = f.[week_start];

GO

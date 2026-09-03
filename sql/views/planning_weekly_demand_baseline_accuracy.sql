USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO


CREATE OR ALTER VIEW [planning].[weekly_demand_baseline_accuracy]
AS

/*
    Accuracy summary for the rolling baseline backtest.

    WAPE is the preferred scale-independent comparison for aggregate planning.
    Bias remains signed: positive values indicate over-forecasting.
*/

SELECT
     [planning_entity]
    ,[baseline_method]
    ,[forecast_horizon_weeks]
    ,COUNT_BIG(*) AS [forecast_count]
    ,SUM([actual_net_units]) AS [actual_net_units]
    ,SUM([forecast_net_units]) AS [forecast_net_units]
    ,SUM([error_units]) AS [bias_units]
    ,AVG(CONVERT(FLOAT, [error_units])) AS [mean_bias_units]
    ,AVG(CONVERT(FLOAT, [absolute_error_units])) AS [mean_absolute_error_units]
    ,SQRT(AVG(POWER(CONVERT(FLOAT, [error_units]), 2))) AS [root_mean_squared_error_units]
    ,SUM(CONVERT(FLOAT, [absolute_error_units]))
        / NULLIF(SUM(ABS(CONVERT(FLOAT, [actual_net_units]))), 0) AS [weighted_absolute_percentage_error]
FROM [planning].[weekly_demand_baseline_backtest]
GROUP BY
     [planning_entity]
    ,[baseline_method]
    ,[forecast_horizon_weeks];

GO

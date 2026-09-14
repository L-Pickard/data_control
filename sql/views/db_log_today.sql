USE [data_control];

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

GO

CREATE OR ALTER VIEW [dbo].[db_log_today]
AS
SELECT [log_id]
    ,CONVERT(DATE, [timestamp]) AS [date]
    ,CONVERT(TIME(7), [timestamp]) AS [time]
    ,[notified]
    ,[duration_seconds]
    ,[level]
    ,[table]
    ,[rows]
    ,[action]
    ,[message]
FROM [dbo].[db_log]
WHERE [timestamp] >= CONVERT(DATE, SYSDATETIME())
    AND [timestamp] < DATEADD(DAY, 1, CONVERT(DATE, SYSDATETIME()));

GO

USE [data_control];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

DROP TABLE IF EXISTS [dbo].[b2b_events];
GO

CREATE TABLE [dbo].[b2b_events] (
     [b2b_event_id] BIGINT IDENTITY(1, 1) NOT NULL
    ,[customer_id] NVARCHAR(20) NULL
    ,[timestamp] DATETIME2(3) NULL
    ,[event] NVARCHAR(30) NULL
    ,CONSTRAINT [PK_b2b_events] PRIMARY KEY CLUSTERED ([b2b_event_id])
);
GO

CREATE NONCLUSTERED INDEX [IX_b2b_events_timestamp]
    ON [dbo].[b2b_events] ([timestamp]);
GO

CREATE NONCLUSTERED INDEX [IX_b2b_events_customer_timestamp]
    ON [dbo].[b2b_events] ([customer_id], [timestamp]);
GO

USE [data_control];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[insert_b2b_events]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @inserted_rows INTEGER = 0;
    DECLARE @transaction_started BIT = 0;

    IF OBJECT_ID(N'dbo.b2b_events', N'U') IS NULL
        THROW 50001, 'dbo.b2b_events does not exist.', 1;

    IF OBJECT_ID(N'dbo.b2b_events_staging', N'U') IS NULL
        THROW 50002, 'dbo.b2b_events_staging does not exist.', 1;

    IF NOT EXISTS (SELECT 1 FROM [dbo].[b2b_events_staging])
        THROW 50003, 'dbo.b2b_events_staging contains no rows.', 1;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaction_started = 1;
        END;

        INSERT INTO [dbo].[b2b_events] (
             [customer_id]
            ,[timestamp]
            ,[event]
        )
        SELECT [customer_id]
            ,[timestamp]
            ,[event]
        FROM [dbo].[b2b_events_staging];

        SET @inserted_rows = @@ROWCOUNT;

        DROP TABLE [dbo].[b2b_events_staging];

        IF @transaction_started = 1
            COMMIT TRANSACTION;

        SELECT @inserted_rows AS [inserted_rows];
    END TRY
    BEGIN CATCH
        IF @transaction_started = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

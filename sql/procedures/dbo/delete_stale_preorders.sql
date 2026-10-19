USE [data_control];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[delete_stale_preorders]
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     13/08/2026
=================================================================================================================================================
Deletes preorder rows that have not appeared in a source load for more than 36 hours. Rows with a source order timestamp are eligible when that
timestamp is within the preceding seven days. Rows using the missing-timestamp placeholder are eligible when first seen within the preceding seven
days. The cutoffs are captured once so every predicate and log message uses the same point in time.
================================================================================================================================================*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @executed_at DATETIME2(7) = SYSDATETIME();
    DECLARE @last_seen_cutoff DATETIME2(7);
    DECLARE @update_freshness_cutoff DATETIME2(7);
    DECLARE @order_start DATETIME2(7);
    DECLARE @rows_deleted INTEGER = 0;
    DECLARE @transaction_started BIT = 0;
    DECLARE @started_at DATETIME2(7) = SYSDATETIME();
    DECLARE @duration_seconds DECIMAL(38, 20);
    DECLARE @message NVARCHAR(MAX);

    SET @last_seen_cutoff   = DATEADD(HOUR, -36, @executed_at);
    SET @update_freshness_cutoff = DATEADD(HOUR, -24, @executed_at);
    SET @order_start        = DATEADD(DAY, -7, @executed_at);

    BEGIN TRY
        IF NOT EXISTS (
            SELECT 1
            FROM [dbo].[preorders]
            WHERE [last_seen_at] >= @update_freshness_cutoff
              AND [last_seen_at] <= @executed_at
        )
            THROW 50003,
                'Preorder cleanup stopped because no preorder row was seen in the last 24 hours.',
                1;

        IF @@TRANCOUNT = 0

        BEGIN
            BEGIN TRANSACTION;
            SET @transaction_started = 1;
        END;

        DELETE FROM [dbo].[preorders]

        WHERE [last_seen_at] < @last_seen_cutoff
          AND (
                (
                    [order_timestamp_missing] = 0
                    AND [order_timestamp] >= @order_start
                    AND [order_timestamp] <= @executed_at
                )
                OR (
                    [order_timestamp_missing] = 1
                    AND [first_seen_at] >= @order_start
                    AND [first_seen_at] <= @executed_at
                )
              );

        SET @rows_deleted = @@ROWCOUNT;

        SET @duration_seconds = CAST(
            DATEDIFF_BIG(MICROSECOND, @started_at, SYSDATETIME()) / 1000000.0
            AS DECIMAL(38, 20)
        );

        SET @message = CONCAT(
             N'Deleted ', @rows_deleted, N' preorder rows last seen before '
            ,CONVERT(NVARCHAR(30), @last_seen_cutoff, 126)
            ,N' with order timestamps from '
            ,CONVERT(NVARCHAR(30), @order_start, 126)
            ,N' through '
            ,CONVERT(NVARCHAR(30), @executed_at, 126)
            ,N'. A preorder source update was observed within the preceding 24 hours.'
        );

        EXEC [dbo].[write_db_log]
             @level = N'SUCCESS'
            ,@table = N'preorders'
            ,@rows = @rows_deleted
            ,@action = N'delete stale recent preorders'
            ,@message = @message
            ,@duration_seconds = @duration_seconds;

        IF @transaction_started = 1
            COMMIT TRANSACTION;

        SELECT
             @rows_deleted              AS [rows_deleted]
            ,@last_seen_cutoff          AS [last_seen_cutoff]
            ,@update_freshness_cutoff   AS [update_freshness_cutoff]
            ,@order_start               AS [order_timestamp_from]
            ,@executed_at               AS [order_timestamp_to];
    END TRY
    BEGIN CATCH
    
        DECLARE @error_message NVARCHAR(4000) = ERROR_MESSAGE();

        IF @transaction_started = 1
           AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        BEGIN TRY
            SET @duration_seconds = CAST(
                DATEDIFF_BIG(MICROSECOND, @started_at, SYSDATETIME()) / 1000000.0
                AS DECIMAL(38, 20)
            );

            EXEC [dbo].[write_db_log]
                 @level = N'FAILURE'
                ,@table = N'preorders'
                ,@rows = NULL
                ,@action = N'delete stale recent preorders'
                ,@message = @error_message
                ,@duration_seconds = @duration_seconds;
        END TRY

        BEGIN CATCH
            -- Preserve and rethrow the original deletion error if logging fails.
        END CATCH;

        THROW;
    END CATCH;
END;
GO

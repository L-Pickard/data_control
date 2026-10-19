USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[start_inventory_cost_job]
AS
-- Starts only inventory_cost_requests via the restricted msdb owner-executed bridge.
-- Returns 0 or the SQL error number. The caller marks a start failure immediately;
-- there is no scheduled retry or waiting queue.

BEGIN
	SET NOCOUNT ON;

	BEGIN TRY
		EXEC [msdb].[dbo].[start_inventory_cost_requests_job];

		RETURN 0;

	END TRY

	BEGIN CATCH
		DECLARE @error INT = ERROR_NUMBER();
		DECLARE @message NVARCHAR(MAX) = CONCAT(N'The inventory_cost_requests job could not be started (error ', @error, N'): ', ERROR_MESSAGE(),
				N' The caller will mark the operation failed. Caller: ', ORIGINAL_LOGIN(), N'.');

		EXEC [dbo].[write_db_log]
				 @level = N'WARNING'
				,@table = N'inventory_cost'
				,@action = N'start inventory cost job'
				,@message = @message;

		RETURN @error;

	END CATCH;
END;

GO

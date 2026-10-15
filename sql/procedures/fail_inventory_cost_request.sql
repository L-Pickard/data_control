USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[fail_inventory_cost_request]
	 @request_kind NVARCHAR(10)
	,@request_id INT
	,@message NVARCHAR(4000)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     15/10/2026
=================================================================================================================================================
Marks a claimed inventory cost check ('running') or dataset ('loading') as failed with the reason, after the job's
own work has been rolled back. Called by the inventory cost job; the portal shows the message. A request that is
no longer running or loading is left as it is.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @message = LEFT(ISNULL(NULLIF(LTRIM(RTRIM(@message)), N''), N'The job failed without a message.'), 4000);

	IF @request_kind = N'check'
		UPDATE [finance].[inventory_cost_checks]

		SET [status] = N'failed'
			,[completed_at] = SYSDATETIME()
			,[message] = @message

		WHERE [check_id] = @request_id
			AND [status] = N'running';
	ELSE IF @request_kind = N'dataset'
		UPDATE [finance].[inventory_cost]

		SET [status] = N'failed'
			,[completed_at] = SYSDATETIME()
			,[message] = @message

		WHERE [dataset_id] = @request_id
			AND [status] = N'loading';
	ELSE
		THROW 50151, 'The @request_kind parameter must be check or dataset.', 1;
END;

GO

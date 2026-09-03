USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [dbo].[write_db_log]
	 @level NVARCHAR(15)
	,@table NVARCHAR(30) = NULL
	,@rows INT = NULL
	,@action NVARCHAR(MAX) = NULL
	,@message NVARCHAR(MAX) = NULL
	,@duration_seconds DECIMAL(38, 20) = 0
AS
BEGIN
	SET NOCOUNT ON;

	INSERT INTO [dbo].[db_log] (
		 [timestamp]
		,[duration_seconds]
		,[level]
		,[table]
		,[rows]
		,[action]
		,[message]
		)
	VALUES (
		 SYSDATETIME()
		,@duration_seconds
		,@level
		,@table
		,@rows
		,@action
		,@message
		);
END;

GO

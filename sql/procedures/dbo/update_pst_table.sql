USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE
	OR

ALTER PROCEDURE [dbo].[update_pst_table]
AS
/*===============================================================================================================================================
Project:  Data Control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     19/10/2026
=================================================================================================================================================

================================================================================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @transaction_started bit = 0;

BEGIN TRY
	IF @@TRANCOUNT = 0
	BEGIN
		BEGIN TRANSACTION;
		SET @transaction_started = 1;
	END;




	IF @transaction_started = 1
		COMMIT TRANSACTION;

END TRY

BEGIN CATCH
	IF @transaction_started = 1 AND XACT_STATE() <> 0
		ROLLBACK TRANSACTION;

	THROW;

END CATCH
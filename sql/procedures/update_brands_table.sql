USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE
	OR

ALTER PROCEDURE [dbo].[update_brands_table]
AS
/*===============================================================================================================================================
Project:  Data Control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     28/05/2026
=================================================================================================================================================
This stored procedure updates the brands table from brands_staging. Matching brand records are deleted from brands, the refreshed staging rows
are inserted, and the staging table is dropped after a successful update.
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

	-- Update existing brands in place so dependent foreign keys remain valid.

	UPDATE br
	SET  br.[brand_name] = bs.[brand_name]
		,br.[buying_category] = bs.[buying_category]
		,br.[brand_group] = bs.[brand_group]
		,br.[revenue_group] = bs.[revenue_group]
	FROM [dbo].[brands] AS br
	INNER JOIN [dbo].[brands_staging] AS bs
		ON bs.[brand_id] = br.[brand_id];

	-- Insert new source brands. Placeholder brands required by facts remain
	-- untouched until they appear in the authoritative brand source.

	INSERT INTO [dbo].[brands] (
		 [brand_id]
		,[brand_name]
		,[buying_category]
		,[brand_group]
		,[revenue_group]
		)
	
	SELECT [brand_id]
		,[brand_name]
		,[buying_category]
		,[brand_group]
		,[revenue_group]
	
	FROM [dbo].[brands_staging] AS bs
	WHERE NOT EXISTS (
		SELECT 1
		FROM [dbo].[brands] AS br
		WHERE br.[brand_id] = bs.[brand_id]
		);

    -- The below command drops the staging table after it is finished being used.

	DROP TABLE

	IF EXISTS [dbo].[brands_staging];
	IF @transaction_started = 1
		COMMIT TRANSACTION;

END TRY

BEGIN CATCH
	IF @transaction_started = 1 AND XACT_STATE() <> 0
		ROLLBACK TRANSACTION;

	THROW;

END CATCH

GO

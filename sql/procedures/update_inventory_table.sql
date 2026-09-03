USE [data_control];
GO

CREATE OR ALTER PROCEDURE [dbo].[update_inventory_table]
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @transaction_started BIT = 0;
	DECLARE @refreshed_at DATETIME2(7) = SYSDATETIME();

	IF OBJECT_ID(N'dbo.inventory_staging', N'U') IS NULL
		THROW 50001, 'dbo.inventory_staging does not exist.', 1;
	IF NOT EXISTS (SELECT 1 FROM [dbo].[inventory_staging])
		THROW 50002, 'dbo.inventory_staging contains no rows.', 1;
	IF EXISTS (
		SELECT [entity], [item_id] FROM [dbo].[inventory_staging]
		GROUP BY [entity], [item_id] HAVING COUNT(*) > 1)
		THROW 50003, 'dbo.inventory_staging contains duplicate business keys.', 1;
	IF EXISTS (
		SELECT 1 FROM [dbo].[inventory_staging]
		WHERE NULLIF(LTRIM(RTRIM([entity])), N'') IS NULL
			OR NULLIF(LTRIM(RTRIM([item_id])), N'') IS NULL
			OR [inventory] IS NULL OR [buffer_stock] IS NULL
			OR [reserved_quantity] IS NULL OR [unavailable_quantity] IS NULL
			OR [inventory] < 0 OR [buffer_stock] < 0
			OR [reserved_quantity] < 0 OR [unavailable_quantity] < 0)
		THROW 50004, 'dbo.inventory_staging contains invalid keys or quantities.', 1;

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;
			SET @transaction_started = 1;
		END;

		INSERT INTO [dbo].[brands] ([brand_id])
		SELECT DISTINCT CAST(LEFT(s.[item_id], 3) AS NVARCHAR(20))
		FROM [dbo].[inventory_staging] AS s
		WHERE NOT EXISTS (
			SELECT 1 FROM [dbo].[brands] AS b
			WHERE b.[brand_id] = CAST(LEFT(s.[item_id], 3) AS NVARCHAR(20)));

		INSERT INTO [dbo].[items] ([item_id], [is_placeholder])
		SELECT DISTINCT s.[item_id], 1
		FROM [dbo].[inventory_staging] AS s
		WHERE NOT EXISTS (
			SELECT 1 FROM [dbo].[items] AS i WHERE i.[item_id] = s.[item_id]);

		DELETE FROM [dbo].[inventory];

		INSERT INTO [dbo].[inventory] (
			[entity], [item_id], [inventory], [buffer_stock],
			[reserved_quantity], [unavailable_quantity], [refreshed_at])
		SELECT [entity], [item_id], [inventory], [buffer_stock],
			[reserved_quantity], [unavailable_quantity], @refreshed_at
		FROM [dbo].[inventory_staging];

		DROP TABLE [dbo].[inventory_staging];

		IF @transaction_started = 1 COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF @transaction_started = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END;
GO

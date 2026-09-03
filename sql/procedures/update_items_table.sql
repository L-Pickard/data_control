USE [data_control];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[update_items_table]
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @transaction_started BIT = 0;

	IF OBJECT_ID(N'dbo.items_staging', N'U') IS NULL
		THROW 50001, 'dbo.items_staging does not exist.', 1;
	IF NOT EXISTS (SELECT 1 FROM [dbo].[items_staging])
		THROW 50002, 'dbo.items_staging contains no rows.', 1;
	IF EXISTS (
		SELECT [item_id] FROM [dbo].[items_staging]
		GROUP BY [item_id]
		HAVING [item_id] IS NULL OR COUNT(*) > 1
	)
		THROW 50003, 'dbo.items_staging contains a NULL or duplicate item_id.', 1;

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;
			SET @transaction_started = 1;
		END;

		CREATE TABLE #referenced_items (
			[item_id] NVARCHAR(20) NOT NULL PRIMARY KEY
		);

		INSERT INTO #referenced_items ([item_id])
		SELECT DISTINCT [item_id]
		FROM [dbo].[purchase_orders]
		WHERE [item_id] IS NOT NULL;

		IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL
			INSERT INTO #referenced_items ([item_id])
			SELECT DISTINCT so.[item_id]
			FROM [dbo].[sales_orders] AS so
			WHERE so.[item_id] IS NOT NULL
				AND NOT EXISTS (
					SELECT 1 FROM #referenced_items AS refs
					WHERE refs.[item_id] = so.[item_id]
				);

		INSERT INTO [dbo].[brands] ([brand_id])
		SELECT refs.[brand_id]
		FROM (
			SELECT DISTINCT CAST(LEFT([item_id], 3) AS NVARCHAR(20)) AS [brand_id]
			FROM [dbo].[items_staging]
			UNION
			SELECT DISTINCT CAST(LEFT([item_id], 3) AS NVARCHAR(20))
			FROM #referenced_items
		) AS refs
		WHERE NOT EXISTS (
			SELECT 1 FROM [dbo].[brands] AS b
			WHERE b.[brand_id] = refs.[brand_id]
		);

		ALTER TABLE [dbo].[purchase_orders]
			NOCHECK CONSTRAINT [FK_purchase_orders_items];
		IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL
			ALTER TABLE [dbo].[sales_orders]
				NOCHECK CONSTRAINT [FK_sales_orders_items];
		IF OBJECT_ID(N'dbo.item_images', N'U') IS NOT NULL
			ALTER TABLE [dbo].[item_images]
				NOCHECK CONSTRAINT [FK_item_images_items];

		DELETE FROM [dbo].[items];

		INSERT INTO [dbo].[items] (
			 [item_id], [is_placeholder], [vendor_reference], [description]
			,[description_2], [colours], [size_1], [size_1_unit], [eu_size]
			,[eu_size_unit], [us_size], [us_size_unit], [season], [item_info]
			,[category_code], [group_code], [ean_barcode], [tariff_no], [hts_no]
			,[gbp_cost], [gbp_trade], [gbp_srp], [eur_cost], [eur_trade], [eur_srp]
			,[usd_cost], [usd_trade], [usd_srp], [royalty], [uk_eu_vendor_no]
			,[us_vendor_no], [ltd_blocked], [bv_blocked], [llc_blocked], [pref_sale]
			,[coo], [unit_of_measure], [hot_product], [lead_time_days], [bread_butter]
			,[ltd_buffer_stock], [bv_buffer_stock], [common_item_no], [d2c_master_sku]
			,[d2c_web_item], [owtanet_export], [web_item], [record_id]
		)
		SELECT
			 [item_id], 0, NULLIF([vendor_reference], N''), NULLIF([description], N'')
			,NULLIF([description_2], N''), NULLIF([colours], N''), NULLIF([size_1], N'')
			,NULLIF([size_1_unit], N''), NULLIF([eu_size], N''), NULLIF([eu_size_unit], N'')
			,NULLIF([us_size], N''), NULLIF([us_size_unit], N''), NULLIF([season], N'')
			,NULLIF([item_info], N''), NULLIF([category_code], N''), NULLIF([group_code], N'')
			,NULLIF([ean_barcode], N''), NULLIF([tariff_no], N''), NULLIF([hts_no], N'')
			,[gbp_cost], [gbp_trade], [gbp_srp], [eur_cost], [eur_trade], [eur_srp]
			,[usd_cost], [usd_trade], [usd_srp], [royalty]
			,NULLIF([uk_eu_vendor_no], N''), NULLIF([us_vendor_no], N'')
			,[ltd_blocked], [bv_blocked], [llc_blocked], [pref_sale]
			,NULLIF([coo], N''), NULLIF([unit_of_measure], N''), [hot_product]
			,[lead_time_days], [bread_butter], [ltd_buffer_stock], [bv_buffer_stock]
			,NULLIF([common_item_no], N''), NULLIF([d2c_master_sku], N'')
			,NULLIF([d2c_web_item], N''), [owtanet_export], [web_item], [record_id]
		FROM [dbo].[items_staging];

		INSERT INTO [dbo].[items] ([item_id], [is_placeholder])
		SELECT refs.[item_id], 1
		FROM #referenced_items AS refs
		WHERE NOT EXISTS (
			SELECT 1 FROM [dbo].[items] AS i
			WHERE i.[item_id] = refs.[item_id]
		);

		IF OBJECT_ID(N'dbo.item_images', N'U') IS NOT NULL
			DELETE ii
			FROM [dbo].[item_images] AS ii
			WHERE NOT EXISTS (
				SELECT 1 FROM [dbo].[items] AS i
				WHERE i.[item_id] = ii.[item_id]
			);

		ALTER TABLE [dbo].[purchase_orders] WITH CHECK
			CHECK CONSTRAINT [FK_purchase_orders_items];
		IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL
			ALTER TABLE [dbo].[sales_orders] WITH CHECK
				CHECK CONSTRAINT [FK_sales_orders_items];
		IF OBJECT_ID(N'dbo.item_images', N'U') IS NOT NULL
			ALTER TABLE [dbo].[item_images] WITH CHECK
				CHECK CONSTRAINT [FK_item_images_items];

		DROP TABLE [dbo].[items_staging];
		IF @transaction_started = 1
			COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF @transaction_started = 1 AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END;
GO

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

		IF OBJECT_ID(N'dbo.sales', N'U') IS NOT NULL
			INSERT INTO #referenced_items ([item_id])
			SELECT DISTINCT s.[item_id]
			FROM [dbo].[sales] AS s
			WHERE s.[item_id] IS NOT NULL
				AND NOT EXISTS (SELECT 1 FROM #referenced_items AS refs WHERE refs.[item_id] = s.[item_id]);

		IF OBJECT_ID(N'dbo.inventory', N'U') IS NOT NULL
            INSERT INTO #referenced_items ([item_id])
            SELECT DISTINCT inv.[item_id]
            FROM [dbo].[inventory] AS inv
            WHERE inv.[item_id] IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM #referenced_items AS refs WHERE refs.[item_id] = inv.[item_id]);

		IF OBJECT_ID(N'dbo.item_inventory_costs', N'U') IS NOT NULL
			INSERT INTO #referenced_items ([item_id])
			SELECT DISTINCT source.[item_id] FROM [dbo].[item_inventory_costs] AS source
			WHERE source.[item_id] IS NOT NULL
			AND NOT EXISTS (SELECT 1 FROM #referenced_items AS refs WHERE refs.[item_id] = source.[item_id]);

		IF OBJECT_ID(N'finance.inventory_cost_lines', N'U') IS NOT NULL
			INSERT INTO #referenced_items ([item_id])
			SELECT DISTINCT source.[item_id] FROM [finance].[inventory_cost_lines] AS source
			WHERE source.[item_id] IS NOT NULL
			AND NOT EXISTS (SELECT 1 FROM #referenced_items AS refs WHERE refs.[item_id] = source.[item_id]);

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

		SELECT TOP (0) [item_id], [is_placeholder], [vendor_reference], [description]
			,[description_2], [colours], [size_1], [size_1_unit]
			,[eu_size], [eu_size_unit], [us_size], [us_size_unit]
			,[season], [item_info], [category_code], [group_code]
			,[ean_barcode], [tariff_no], [hts_no], [gbp_cost]
			,[gbp_trade], [gbp_srp], [eur_cost], [eur_trade]
			,[eur_srp], [usd_cost], [usd_trade], [usd_srp]
			,[royalty], [uk_eu_vendor_no], [us_vendor_no], [ltd_blocked]
			,[bv_blocked], [llc_blocked], [pref_sale], [coo]
			,[unit_of_measure], [hot_product], [lead_time_days], [lead_time_months], [bread_butter]
			,[ltd_buffer_stock], [bv_buffer_stock], [common_item_no], [d2c_master_sku]
			,[d2c_web_item], [owtanet_export], [web_item], [record_id]
		INTO #new_items FROM [dbo].[items];

		INSERT INTO #new_items (
			 [item_id], [is_placeholder], [vendor_reference], [description]
			,[description_2], [colours], [size_1], [size_1_unit], [eu_size]
			,[eu_size_unit], [us_size], [us_size_unit], [season], [item_info]
			,[category_code], [group_code], [ean_barcode], [tariff_no], [hts_no]
			,[gbp_cost], [gbp_trade], [gbp_srp], [eur_cost], [eur_trade], [eur_srp]
			,[usd_cost], [usd_trade], [usd_srp], [royalty], [uk_eu_vendor_no]
			,[us_vendor_no], [ltd_blocked], [bv_blocked], [llc_blocked], [pref_sale]
			,[coo], [unit_of_measure], [hot_product], [lead_time_days], [lead_time_months], [bread_butter]
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
			,[lead_time_days], [lead_time_months], [bread_butter], [ltd_buffer_stock], [bv_buffer_stock]
			,NULLIF([common_item_no], N''), NULLIF([d2c_master_sku], N'')
			,NULLIF([d2c_web_item], N''), [owtanet_export], [web_item], [record_id]
		FROM [dbo].[items_staging];

		-- Refresh existing keys without breaking references from saved datasets.
		UPDATE target SET
			target.[is_placeholder] = source.[is_placeholder],
			target.[vendor_reference] = source.[vendor_reference],
			target.[description] = source.[description],
			target.[description_2] = source.[description_2],
			target.[colours] = source.[colours],
			target.[size_1] = source.[size_1],
			target.[size_1_unit] = source.[size_1_unit],
			target.[eu_size] = source.[eu_size],
			target.[eu_size_unit] = source.[eu_size_unit],
			target.[us_size] = source.[us_size],
			target.[us_size_unit] = source.[us_size_unit],
			target.[season] = source.[season],
			target.[item_info] = source.[item_info],
			target.[category_code] = source.[category_code],
			target.[group_code] = source.[group_code],
			target.[ean_barcode] = source.[ean_barcode],
			target.[tariff_no] = source.[tariff_no],
			target.[hts_no] = source.[hts_no],
			target.[gbp_cost] = source.[gbp_cost],
			target.[gbp_trade] = source.[gbp_trade],
			target.[gbp_srp] = source.[gbp_srp],
			target.[eur_cost] = source.[eur_cost],
			target.[eur_trade] = source.[eur_trade],
			target.[eur_srp] = source.[eur_srp],
			target.[usd_cost] = source.[usd_cost],
			target.[usd_trade] = source.[usd_trade],
			target.[usd_srp] = source.[usd_srp],
			target.[royalty] = source.[royalty],
			target.[uk_eu_vendor_no] = source.[uk_eu_vendor_no],
			target.[us_vendor_no] = source.[us_vendor_no],
			target.[ltd_blocked] = source.[ltd_blocked],
			target.[bv_blocked] = source.[bv_blocked],
			target.[llc_blocked] = source.[llc_blocked],
			target.[pref_sale] = source.[pref_sale],
			target.[coo] = source.[coo],
			target.[unit_of_measure] = source.[unit_of_measure],
			target.[hot_product] = source.[hot_product],
			target.[lead_time_days] = source.[lead_time_days],
			target.[lead_time_months] = source.[lead_time_months],
			target.[bread_butter] = source.[bread_butter],
			target.[ltd_buffer_stock] = source.[ltd_buffer_stock],
			target.[bv_buffer_stock] = source.[bv_buffer_stock],
			target.[common_item_no] = source.[common_item_no],
			target.[d2c_master_sku] = source.[d2c_master_sku],
			target.[d2c_web_item] = source.[d2c_web_item],
			target.[owtanet_export] = source.[owtanet_export],
			target.[web_item] = source.[web_item],
			target.[record_id] = source.[record_id]
		FROM [dbo].[items] AS target
		JOIN #new_items AS source ON source.[item_id] = target.[item_id];

		INSERT INTO [dbo].[items] ([item_id], [is_placeholder], [vendor_reference], [description]
			,[description_2], [colours], [size_1], [size_1_unit]
			,[eu_size], [eu_size_unit], [us_size], [us_size_unit]
			,[season], [item_info], [category_code], [group_code]
			,[ean_barcode], [tariff_no], [hts_no], [gbp_cost]
			,[gbp_trade], [gbp_srp], [eur_cost], [eur_trade]
			,[eur_srp], [usd_cost], [usd_trade], [usd_srp]
			,[royalty], [uk_eu_vendor_no], [us_vendor_no], [ltd_blocked]
			,[bv_blocked], [llc_blocked], [pref_sale], [coo]
			,[unit_of_measure], [hot_product], [lead_time_days], [lead_time_months], [bread_butter]
			,[ltd_buffer_stock], [bv_buffer_stock], [common_item_no], [d2c_master_sku]
			,[d2c_web_item], [owtanet_export], [web_item], [record_id])
		SELECT source.[item_id], source.[is_placeholder], source.[vendor_reference], source.[description]
			,source.[description_2], source.[colours], source.[size_1], source.[size_1_unit]
			,source.[eu_size], source.[eu_size_unit], source.[us_size], source.[us_size_unit]
			,source.[season], source.[item_info], source.[category_code], source.[group_code]
			,source.[ean_barcode], source.[tariff_no], source.[hts_no], source.[gbp_cost]
			,source.[gbp_trade], source.[gbp_srp], source.[eur_cost], source.[eur_trade]
			,source.[eur_srp], source.[usd_cost], source.[usd_trade], source.[usd_srp]
			,source.[royalty], source.[uk_eu_vendor_no], source.[us_vendor_no], source.[ltd_blocked]
			,source.[bv_blocked], source.[llc_blocked], source.[pref_sale], source.[coo]
			,source.[unit_of_measure], source.[hot_product], source.[lead_time_days], source.[lead_time_months], source.[bread_butter]
			,source.[ltd_buffer_stock], source.[bv_buffer_stock], source.[common_item_no], source.[d2c_master_sku]
			,source.[d2c_web_item], source.[owtanet_export], source.[web_item], source.[record_id]
		FROM #new_items AS source
		WHERE NOT EXISTS (SELECT 1 FROM [dbo].[items] AS target WHERE target.[item_id] = source.[item_id]);

		INSERT INTO [dbo].[items] ([item_id], [is_placeholder])
		SELECT refs.[item_id], 1
		FROM #referenced_items AS refs
		WHERE NOT EXISTS (
			SELECT 1 FROM [dbo].[items] AS i
			WHERE i.[item_id] = refs.[item_id]
		);

		IF OBJECT_ID(N'dbo.item_images', N'U') IS NOT NULL
			DELETE images FROM [dbo].[item_images] AS images
			WHERE NOT EXISTS (SELECT 1 FROM #new_items AS source WHERE source.[item_id] = images.[item_id])
			AND NOT EXISTS (SELECT 1 FROM #referenced_items AS refs WHERE refs.[item_id] = images.[item_id]);

		DELETE target FROM [dbo].[items] AS target
		WHERE NOT EXISTS (SELECT 1 FROM #new_items AS source WHERE source.[item_id] = target.[item_id])
		AND NOT EXISTS (SELECT 1 FROM #referenced_items AS refs WHERE refs.[item_id] = target.[item_id]);

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

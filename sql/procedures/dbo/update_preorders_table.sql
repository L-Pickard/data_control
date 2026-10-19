USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

CREATE
	OR

ALTER PROCEDURE [dbo].[update_preorders_table] @source_type NVARCHAR(10)
AS
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	DECLARE @now DATETIME2(7) = SYSDATETIME();

	DECLARE @updated_rows INTEGER = 0;

	DECLARE @inserted_rows INTEGER = 0;

	DECLARE @retired_rows INTEGER = 0;

	DECLARE @placeholder_timestamp_rows INTEGER = 0;

	DECLARE @transaction_started BIT = 0;

	IF @source_type NOT IN (N'current', N'history') THROW 50001
		,'source_type must be current or history.'
		,1;

		CREATE TABLE [#preorders_source] (
			 [file_source] NVARCHAR(20) NOT NULL
			,[preorder_code] NVARCHAR(50) NULL
			,[item_id] NVARCHAR(50) NULL
			,[description] NVARCHAR(300) NULL
			,[customer_id] NVARCHAR(20) NULL
			,[order_timestamp] DATETIME2(3) NOT NULL
			,[order_timestamp_missing] BIT NOT NULL
			,[season] NVARCHAR(20) NULL
			,[type] INTEGER NULL
			,[brand_code] NVARCHAR(20) NULL
			,[category_code] NVARCHAR(20) NULL
			,[country_id] NVARCHAR(10) NULL
			,[quantity] DECIMAL(38, 20) NULL
			,[value] DECIMAL(38, 20) NULL
			,[currency_code] NVARCHAR(10) NULL
			,[start_timestamp] DATETIME2(3) NULL
			,[end_timestamp] DATETIME2(3) NULL
			,[eta_timestamp] DATETIME2(3) NULL
			,[is_current] BIT NOT NULL
			);

	IF @source_type = N'current'
	BEGIN
		IF OBJECT_ID(N'dbo.preorders_staging', N'U') IS NULL THROW 50002
			,'dbo.preorders_staging does not exist.'
			,1;
			INSERT INTO [#preorders_source]
			
			SELECT N'current'
				,s.[preorder_code]
				,s.[item_id]
				,s.[description]
				,s.[customer_id]
				,ISNULL(s.[order_timestamp], CONVERT(DATETIME2(3), '1753-01-01T00:00:00.000'))
				,CAST(CASE WHEN s.[order_timestamp] IS NULL THEN 1 ELSE 0 END AS BIT)
				,s.[season]
				,s.[type]
				,s.[brand_code]
				,s.[category_code]
				,s.[country_id]
				,s.[quantity]
				,s.[value]
				,s.[currency_code]
				,s.[preorder_start]
				,s.[preorder_end]
				,s.[delivery_eta]
				,CAST(1 AS BIT)
			
			FROM [dbo].[preorders_staging] AS s;
	
	END
	
	ELSE
	BEGIN
		IF OBJECT_ID(N'dbo.preorders_history_staging', N'U') IS NULL THROW 50003
			,'dbo.preorders_history_staging does not exist.'
			,1;

			INSERT INTO [#preorders_source]
			
			SELECT N'history'
				,s.[preorder_code]
				,s.[item_id]
				,s.[description]
				,s.[customer_id]
				,ISNULL(s.[order_timestamp], CONVERT(DATETIME2(3), '1753-01-01T00:00:00.000'))
				,CAST(CASE WHEN s.[order_timestamp] IS NULL THEN 1 ELSE 0 END AS BIT)
				,s.[season]
				,s.[type]
				,s.[brand_code]
				,s.[category_code]
				,s.[country_id]
				,s.[quantity]
				,s.[value]
				,s.[currency_code]
				,s.[preorder_start]
				,s.[preorder_end]
				,s.[delivery_eta]
				,CAST(0 AS BIT)
			
			FROM [dbo].[preorders_history_staging] AS s;
	
	END;

	SELECT @placeholder_timestamp_rows = COUNT(*)
	
	FROM [#preorders_source]
	
	WHERE [order_timestamp_missing] = 1;

	IF NOT EXISTS (
			SELECT 1
			
			FROM [#preorders_source]
			) THROW 50004
		,'The preorder staging table contains no rows.'
		,1;
		IF EXISTS (
				SELECT 1
				
				FROM [#preorders_source]
				
				WHERE NULLIF(LTRIM(RTRIM([preorder_code])), N'') IS NULL
					OR NULLIF(LTRIM(RTRIM([customer_id])), N'') IS NULL
					OR NULLIF(LTRIM(RTRIM([currency_code])), N'') IS NULL
				) THROW 50005
			,'The preorder staging table contains a NULL or blank business key.'
			,1;
			SELECT TOP (0) *
			
			INTO [#preorders_aggregated]
			
			FROM [#preorders_source];

	INSERT INTO [#preorders_aggregated]
	
	SELECT MAX([file_source])
		,[preorder_code]
		,MAX(NULLIF(LTRIM(RTRIM([item_id])), N''))
		,MAX(ISNULL(NULLIF(LTRIM(RTRIM([description])), N''), N''))
		,[customer_id]
		,[order_timestamp]
		,CAST(MAX(CAST([order_timestamp_missing] AS TINYINT)) AS BIT)
		,MAX([season])
		,MAX([type])
		,MAX([brand_code])
		,MAX([category_code])
		,MAX([country_id])
		,SUM([quantity])
		,SUM([value])
		,[currency_code]
		,MAX([start_timestamp])
		,MAX([end_timestamp])
		,MAX([eta_timestamp])
        ,CAST(MAX(CAST([is_current] AS TINYINT)) AS BIT)
	
	FROM [#preorders_source]
	
	GROUP BY [preorder_code]
		,CASE 
			WHEN NULLIF(LTRIM(RTRIM([item_id])), N'') IS NOT NULL
				THEN N'I:' + LTRIM(RTRIM([item_id]))
			ELSE N'D:' + ISNULL(LTRIM(RTRIM([description])), N'')
			END
		,[customer_id]
		,[currency_code]
		,[order_timestamp]
		,[order_timestamp_missing];

	TRUNCATE TABLE [#preorders_source];

	INSERT INTO [#preorders_source]
	
	SELECT *
	
	FROM [#preorders_aggregated];

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;
		
		END;

		/*=============================================================================================================
		TEMPORARY FINANCE COMPATIBILITY SECTION

		Maintain the legacy Finance preorder tables while dependent reports and internal data sources are migrated to
		[data_control].[dbo].[preorders]. The current load rebuilds [Finance].[dbo].[fPreorder] from
		[dbo].[preorders_staging]; the history load rebuilds [Finance].[dbo].[fPreorder History] from
		[dbo].[preorders_history_staging]. Remove this entire section after all consumers use data_control directly.
		=============================================================================================================*/
		IF @source_type = N'current'
		BEGIN
			DROP TABLE IF EXISTS [Finance].[dbo].[fPreorder];

			CREATE TABLE [Finance].[dbo].[fPreorder] (
				 [Preorder Code] NVARCHAR(70) NULL
				,[Season] NVARCHAR(20) NULL
				,[Type] INTEGER NULL
				,[Brand Code] NVARCHAR(3) NULL
				,[Category Code] NVARCHAR(50) NULL
				,[Item No] NVARCHAR(30) NULL
				,[Item Description] NVARCHAR(300) NULL
				,[Customer No] NVARCHAR(12) NULL
				,[Country Code] NVARCHAR(5) NULL
				,[Quantity] INTEGER NULL
				,[Value] DECIMAL(20, 8) NULL
				,[Currency] NVARCHAR(3) NULL
				,[Order Timestamp] DATETIME2(3) NULL
				,[Start Timestamp] DATETIME2(3) NULL
				,[End Timestamp] DATETIME2(3) NULL
				,[ETA Timestamp] DATETIME2(3) NULL
			);

			INSERT INTO [Finance].[dbo].[fPreorder]
			SELECT CAST([preorder_code] AS NVARCHAR(70))
				,CAST([season] AS NVARCHAR(20))
				,[type]
				,CAST([brand_code] AS NVARCHAR(3))
				,CAST([category_code] AS NVARCHAR(50))
				,CAST([item_id] AS NVARCHAR(30))
				,CAST(ISNULL([description], N'') AS NVARCHAR(300))
				,CAST([customer_id] AS NVARCHAR(12))
				,CAST([country_id] AS NVARCHAR(5))
				,CAST([quantity] AS INTEGER)
				,CAST([value] AS DECIMAL(20, 8))
				,CAST([currency_code] AS NVARCHAR(3))
				,ISNULL(
					 [order_timestamp]
					,CONVERT(DATETIME2(3), '1753-01-01T00:00:00.000')
				)
				,[preorder_start]
				,[preorder_end]
				,[delivery_eta]
			FROM [dbo].[preorders_staging];

			CREATE NONCLUSTERED INDEX [IDX_Preorder_Code] ON [Finance].[dbo].[fPreorder] ([Preorder Code]);
			CREATE NONCLUSTERED INDEX [IDX_Season] ON [Finance].[dbo].[fPreorder] ([Season]);
			CREATE NONCLUSTERED INDEX [IDX_Type] ON [Finance].[dbo].[fPreorder] ([Type]);
			CREATE NONCLUSTERED INDEX [IDX_Brand_Code] ON [Finance].[dbo].[fPreorder] ([Brand Code]);
			CREATE NONCLUSTERED INDEX [IDX_Category_Code] ON [Finance].[dbo].[fPreorder] ([Category Code]);
			CREATE NONCLUSTERED INDEX [IDX_Item_No] ON [Finance].[dbo].[fPreorder] ([Item No]);
			CREATE NONCLUSTERED INDEX [IDX_Item_Description] ON [Finance].[dbo].[fPreorder] ([Item Description]);
			CREATE NONCLUSTERED INDEX [IDX_Customer_No] ON [Finance].[dbo].[fPreorder] ([Customer No]);
			CREATE NONCLUSTERED INDEX [IDX_Country_Code] ON [Finance].[dbo].[fPreorder] ([Country Code]);
			CREATE NONCLUSTERED INDEX [IDX_Quantity] ON [Finance].[dbo].[fPreorder] ([Quantity]);
			CREATE NONCLUSTERED INDEX [IDX_Value] ON [Finance].[dbo].[fPreorder] ([Value]);
			CREATE NONCLUSTERED INDEX [IDX_Currency] ON [Finance].[dbo].[fPreorder] ([Currency]);
			CREATE NONCLUSTERED INDEX [IDX_Order_Timestamp] ON [Finance].[dbo].[fPreorder] ([Order Timestamp]);
			CREATE NONCLUSTERED INDEX [IDX_Start_Timestamp] ON [Finance].[dbo].[fPreorder] ([Start Timestamp]);
			CREATE NONCLUSTERED INDEX [IDX_End_Timestamp] ON [Finance].[dbo].[fPreorder] ([End Timestamp]);
			CREATE NONCLUSTERED INDEX [IDX_ETA_Timestamp] ON [Finance].[dbo].[fPreorder] ([ETA Timestamp]);
		END;
		ELSE
		BEGIN
			DROP TABLE IF EXISTS [Finance].[dbo].[fPreorder History];

			CREATE TABLE [Finance].[dbo].[fPreorder History] (
				 [Preorder Code] NVARCHAR(70) NULL
				,[Season] NVARCHAR(20) NULL
				,[Type] INTEGER NULL
				,[Brand Code] NVARCHAR(3) NULL
				,[Category Code] NVARCHAR(50) NULL
				,[Item No] NVARCHAR(30) NULL
				,[Item Description] NVARCHAR(300) NULL
				,[Customer No] NVARCHAR(12) NULL
				,[Country Code] NVARCHAR(5) NULL
				,[Quantity] INTEGER NULL
				,[Value] DECIMAL(20, 8) NULL
				,[Currency] NVARCHAR(3) NULL
				,[Order Timestamp] DATETIME2(3) NULL
				,[Start Timestamp] DATETIME2(3) NULL
				,[End Timestamp] DATETIME2(3) NULL
				,[ETA Timestamp] DATETIME2(3) NULL
			);

			INSERT INTO [Finance].[dbo].[fPreorder History]
			SELECT CAST([preorder_code] AS NVARCHAR(70))
				,CAST([season] AS NVARCHAR(20))
				,[type]
				,CAST([brand_code] AS NVARCHAR(3))
				,CAST([category_code] AS NVARCHAR(50))
				,CAST([item_id] AS NVARCHAR(30))
				,CAST(ISNULL([description], N'') AS NVARCHAR(300))
				,CAST([customer_id] AS NVARCHAR(12))
				,CAST([country_id] AS NVARCHAR(5))
				,CAST([quantity] AS INTEGER)
				,CAST([value] AS DECIMAL(20, 8))
				,CAST([currency_code] AS NVARCHAR(3))
				,ISNULL(
					 [order_timestamp]
					,CONVERT(DATETIME2(3), '1753-01-01T00:00:00.000')
				)
				,[preorder_start]
				,[preorder_end]
				,[delivery_eta]
			FROM [dbo].[preorders_history_staging];

			CREATE NONCLUSTERED INDEX [IDX_Preorder_Code] ON [Finance].[dbo].[fPreorder History] ([Preorder Code]);
			CREATE NONCLUSTERED INDEX [IDX_Season] ON [Finance].[dbo].[fPreorder History] ([Season]);
			CREATE NONCLUSTERED INDEX [IDX_Type] ON [Finance].[dbo].[fPreorder History] ([Type]);
			CREATE NONCLUSTERED INDEX [IDX_Brand_Code] ON [Finance].[dbo].[fPreorder History] ([Brand Code]);
			CREATE NONCLUSTERED INDEX [IDX_Category_Code] ON [Finance].[dbo].[fPreorder History] ([Category Code]);
			CREATE NONCLUSTERED INDEX [IDX_Item_No] ON [Finance].[dbo].[fPreorder History] ([Item No]);
			CREATE NONCLUSTERED INDEX [IDX_Item_Description] ON [Finance].[dbo].[fPreorder History] ([Item Description]);
			CREATE NONCLUSTERED INDEX [IDX_Customer_No] ON [Finance].[dbo].[fPreorder History] ([Customer No]);
			CREATE NONCLUSTERED INDEX [IDX_Country_Code] ON [Finance].[dbo].[fPreorder History] ([Country Code]);
			CREATE NONCLUSTERED INDEX [IDX_Quantity] ON [Finance].[dbo].[fPreorder History] ([Quantity]);
			CREATE NONCLUSTERED INDEX [IDX_Value] ON [Finance].[dbo].[fPreorder History] ([Value]);
			CREATE NONCLUSTERED INDEX [IDX_Currency] ON [Finance].[dbo].[fPreorder History] ([Currency]);
			CREATE NONCLUSTERED INDEX [IDX_Order_Timestamp] ON [Finance].[dbo].[fPreorder History] ([Order Timestamp]);
			CREATE NONCLUSTERED INDEX [IDX_Start_Timestamp] ON [Finance].[dbo].[fPreorder History] ([Start Timestamp]);
			CREATE NONCLUSTERED INDEX [IDX_End_Timestamp] ON [Finance].[dbo].[fPreorder History] ([End Timestamp]);
			CREATE NONCLUSTERED INDEX [IDX_ETA_Timestamp] ON [Finance].[dbo].[fPreorder History] ([ETA Timestamp]);
		END;
		/*======================================= END TEMPORARY FINANCE COMPATIBILITY SECTION =======================================*/

		UPDATE p
		
		SET p.[file_source] = s.[file_source]
			,p.[description] = s.[description]
			,p.[order_timestamp_missing] = s.[order_timestamp_missing]
			,p.[season] = s.[season]
			,p.[type] = s.[type]
			,p.[brand_code] = s.[brand_code]
			,p.[category_code] = s.[category_code]
			,p.[country_id] = s.[country_id]
			,p.[quantity] = s.[quantity]
			,p.[value] = s.[value]
			,p.[start_timestamp] = s.[start_timestamp]
			,p.[end_timestamp] = s.[end_timestamp]
			,p.[eta_timestamp] = s.[eta_timestamp]
			,p.[is_current] = s.[is_current]
			,p.[last_seen_at] = @now
			,p.[last_changed_at] = @now
		
		FROM [dbo].[preorders] AS p
		
		INNER JOIN [#preorders_source] AS s
			ON s.[preorder_code] = p.[preorder_code]
				AND p.[line_key] = CASE 
					WHEN NULLIF(LTRIM(RTRIM(s.[item_id])), N'') IS NOT NULL
						THEN N'I:' + LTRIM(RTRIM(s.[item_id]))
					ELSE N'D:' + ISNULL(LTRIM(RTRIM(s.[description])), N'')
					END
				AND s.[customer_id] = p.[customer_id]
				AND s.[currency_code] = p.[currency_code]
				AND s.[order_timestamp] = p.[order_timestamp]
				AND s.[order_timestamp_missing] = p.[order_timestamp_missing]
		
		WHERE NOT (
				@source_type = N'history'
				AND p.[is_current] = 1
				)
			AND EXISTS (
				SELECT p.[file_source]
					,p.[description]
					,p.[order_timestamp_missing]
					,p.[season]
					,p.[type]
					,p.[brand_code]
					,p.[category_code]
					,p.[country_id]
					,p.[quantity]
					,p.[value]
					,p.[start_timestamp]
					,p.[end_timestamp]
					,p.[eta_timestamp]
					,p.[is_current]
				
				
				EXCEPT
				
				SELECT s.[file_source]
					,s.[description]
					,s.[order_timestamp_missing]
					,s.[season]
					,s.[type]
					,s.[brand_code]
					,s.[category_code]
					,s.[country_id]
					,s.[quantity]
					,s.[value]
					,s.[start_timestamp]
					,s.[end_timestamp]
					,s.[eta_timestamp]
					,s.[is_current]
				);

		SET @updated_rows = @@ROWCOUNT;

		UPDATE p
		
		SET p.[last_seen_at] = @now
		
		FROM [dbo].[preorders] AS p
		
		INNER JOIN [#preorders_source] AS s
			ON s.[preorder_code] = p.[preorder_code]
				AND p.[line_key] = CASE 
					WHEN NULLIF(LTRIM(RTRIM(s.[item_id])), N'') IS NOT NULL
						THEN N'I:' + LTRIM(RTRIM(s.[item_id]))
					ELSE N'D:' + ISNULL(LTRIM(RTRIM(s.[description])), N'')
					END
				AND s.[customer_id] = p.[customer_id]
				AND s.[currency_code] = p.[currency_code]
				AND s.[order_timestamp] = p.[order_timestamp]
				AND s.[order_timestamp_missing] = p.[order_timestamp_missing]
		
		WHERE NOT (
				@source_type = N'history'
				AND p.[is_current] = 1
				)
			AND p.[last_seen_at] <> @now;

		IF @source_type = N'current'

		BEGIN
			UPDATE p
			
			SET p.[is_current] = 0
				,p.[last_changed_at] = @now
			
			FROM [dbo].[preorders] AS p
			
			WHERE p.[is_current] = 1
				AND NOT EXISTS (
					SELECT 1
					
					FROM [#preorders_source] AS s
					
					WHERE s.[preorder_code] = p.[preorder_code]
						AND p.[line_key] = CASE 
							WHEN NULLIF(LTRIM(RTRIM(s.[item_id])), N'') IS NOT NULL
								THEN N'I:' + LTRIM(RTRIM(s.[item_id]))
							ELSE N'D:' + ISNULL(LTRIM(RTRIM(s.[description])), N'')
							END
						AND s.[customer_id] = p.[customer_id]
						AND s.[currency_code] = p.[currency_code]
						AND s.[order_timestamp] = p.[order_timestamp]
						AND s.[order_timestamp_missing] = p.[order_timestamp_missing]
					);

			SET @retired_rows = @@ROWCOUNT;
		
		END;

		INSERT INTO [dbo].[preorders] (
			 [file_source]
			,[preorder_code]
			,[item_id]
			,[description]
			,[customer_id]
			,[order_timestamp]
			,[order_timestamp_missing]
			,[season]
			,[type]
			,[brand_code]
			,[category_code]
			,[country_id]
			,[quantity]
			,[value]
			,[currency_code]
			,[start_timestamp]
			,[end_timestamp]
			,[eta_timestamp]
			,[is_current]
			,[first_seen_at]
			,[last_seen_at]
			,[last_changed_at]
			)
		
		SELECT s.[file_source]
			,s.[preorder_code]
			,s.[item_id]
			,s.[description]
			,s.[customer_id]
			,s.[order_timestamp]
			,s.[order_timestamp_missing]
			,s.[season]
			,s.[type]
			,s.[brand_code]
			,s.[category_code]
			,s.[country_id]
			,s.[quantity]
			,s.[value]
			,s.[currency_code]
			,s.[start_timestamp]
			,s.[end_timestamp]
			,s.[eta_timestamp]
			,s.[is_current]
			,@now
			,@now
			,@now
		
		FROM [#preorders_source] AS s
		
		WHERE NOT EXISTS (
				SELECT 1
				
				FROM [dbo].[preorders] AS p WITH (
						 UPDLOCK
						,HOLDLOCK
						)
				
				WHERE p.[preorder_code] = s.[preorder_code]
					AND p.[line_key] = CASE 
						WHEN NULLIF(LTRIM(RTRIM(s.[item_id])), N'') IS NOT NULL
							THEN N'I:' + LTRIM(RTRIM(s.[item_id]))
						ELSE N'D:' + ISNULL(LTRIM(RTRIM(s.[description])), N'')
						END
					AND p.[customer_id] = s.[customer_id]
					AND p.[currency_code] = s.[currency_code]
					AND p.[order_timestamp] = s.[order_timestamp]
					AND p.[order_timestamp_missing] = s.[order_timestamp_missing]
				);

		SET @inserted_rows = @@ROWCOUNT;

		EXECUTE [dbo].[delete_stale_preorders];

		IF @source_type = N'current'
		BEGIN
			DROP TABLE [dbo].[preorders_staging];

			EXECUTE [Finance].[dbo].[Preorder Customer Activity Alert V2];
		END;
		
		ELSE
			DROP TABLE [dbo].[preorders_history_staging];

		IF @transaction_started = 1
			COMMIT TRANSACTION;

		SELECT @inserted_rows AS [inserted_rows]
			,@updated_rows AS [updated_rows]
			,@retired_rows AS [retired_rows]
			,@placeholder_timestamp_rows AS [placeholder_timestamp_rows];
	
	END TRY

	BEGIN CATCH
		IF @transaction_started = 1
			AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		THROW;
	
	END CATCH;

END;

GO

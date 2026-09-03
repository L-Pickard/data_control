USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

CREATE
	OR

ALTER PROCEDURE [dbo].[update_preorder_lines_table]
AS
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	DECLARE @refreshed_rows INTEGER = 0;

	DECLARE @transaction_started BIT = 0;

	IF OBJECT_ID(N'dbo.preorder_lines_staging', N'U') IS NULL THROW 50001
		,'dbo.preorder_lines_staging does not exist.'
		,1;
		IF NOT EXISTS (
				SELECT 1
				
				FROM [dbo].[preorder_lines_staging]
				) THROW 50002
			,'dbo.preorder_lines_staging contains no rows.'
			,1;
		BEGIN TRY
			IF @@TRANCOUNT = 0
			BEGIN
				BEGIN TRANSACTION;

				SET @transaction_started = 1;
			
			END;

			DROP TABLE

			IF EXISTS [dbo].[preorder_lines];
				CREATE TABLE [dbo].[preorder_lines] (
					[row_no] INTEGER IDENTITY(1, 1) NOT NULL
					,[preorder_code] NVARCHAR(50) NULL
					,[region] NVARCHAR(10) NULL
					,[brand_code] NVARCHAR(20) NULL
					,[type] INTEGER NULL
					,[season] NVARCHAR(20) NULL
					,[item_id] NVARCHAR(50) NULL
					,[description] NVARCHAR(300) NULL
					,[price_string] NVARCHAR(50) NULL
					,[currency_code] AS CAST(CASE 
							WHEN LEFT([price_string], 2) = N'C_'
								AND CHARINDEX(N'=', [price_string]) > 3
								THEN SUBSTRING([price_string], 3, CHARINDEX(N'=', [price_string]) - 3)
							END AS NVARCHAR(10)) PERSISTED
					,[trade_price] AS TRY_CONVERT(DECIMAL(38, 20), CASE 
							WHEN CHARINDEX(N'=', [price_string]) > 0
								AND CHARINDEX(N' SRP=', [price_string]) > CHARINDEX(N'=', [price_string]) + 1
								THEN SUBSTRING([price_string], CHARINDEX(N'=', [price_string]) + 1, CHARINDEX(N' SRP=', [price_string]) - CHARINDEX(N'=', 
											[price_string]) - 1)
							END) PERSISTED
					,[srp_price] AS TRY_CONVERT(DECIMAL(38, 20), CASE 
							WHEN CHARINDEX(N' SRP=', [price_string]) > 0
								AND CHARINDEX(N' SRP=', [price_string]) + LEN(N' SRP=') <= LEN([price_string])
								THEN SUBSTRING([price_string], CHARINDEX(N' SRP=', [price_string]) + LEN(N' SRP='), LEN([price_string]))
							END) PERSISTED
					,CONSTRAINT [PK_preorder_lines] PRIMARY KEY CLUSTERED ([row_no])
					);

			INSERT INTO [dbo].[preorder_lines] (
				[preorder_code]
				,[region]
				,[brand_code]
				,[type]
				,[season]
				,[item_id]
				,[description]
				,[price_string]
				)
			
			SELECT [preorder_code]
				,[region]
				,[brand_code]
				,[type]
				,[season]
				,[item_id]
				,[description]
				,[price_string]
			
			FROM [dbo].[preorder_lines_staging];

			SET @refreshed_rows = @@ROWCOUNT;

			CREATE NONCLUSTERED INDEX [IX_preorder_lines_preorder_currency_item] ON [dbo].[preorder_lines] (
				[preorder_code]
				,[currency_code]
				,[item_id]
				) INCLUDE (
				[trade_price]
				,[srp_price]
				);

			CREATE NONCLUSTERED INDEX [IX_preorder_lines_item] ON [dbo].[preorder_lines] ([item_id]) INCLUDE (
				[preorder_code]
				,[currency_code]
				,[trade_price]
				,[srp_price]
				);

		/*=============================================================================================================
        TEMPORARY FINANCE COMPATIBILITY SECTION

        Maintain [Finance].[dbo].[dPreorder Lines] while dependent reports and internal data sources are migrated to
        [data_control].[dbo].[preorder_lines]. Remove this entire section after all consumers use data_control directly.
        =============================================================================================================*/
			DROP TABLE

			IF EXISTS [Finance].[dbo].[dPreorder Lines];
				CREATE TABLE [Finance].[dbo].[dPreorder Lines] (
					[Preorder Code] NVARCHAR(70) NULL
					,[Region] NVARCHAR(10) NULL
					,[Brand Code] NVARCHAR(3) NULL
					,[Type] INTEGER NULL
					,[Season] NVARCHAR(20) NULL
					,[Item No] NVARCHAR(40) NULL
					,[Item Description] NVARCHAR(300) NULL
					,[Price String] NVARCHAR(30) NULL
					,[Currency] NVARCHAR(3) NULL
					,[WHS] DECIMAL(20, 8) NULL
					,[SRP] DECIMAL(20, 8) NULL
					,[Row No] INTEGER IDENTITY(1, 1) NOT NULL
					,CONSTRAINT [PK_dPreorder_Lines] PRIMARY KEY CLUSTERED ([Row No])
					);

			INSERT INTO [Finance].[dbo].[dPreorder Lines] (
				 [Preorder Code]
				,[Region]
				,[Brand Code]
				,[Type]
				,[Season]
				,[Item No]
				,[Item Description]
				,[Price String]
				,[Currency]
				,[WHS]
				,[SRP]
				)
			
			SELECT CAST([preorder_code] AS NVARCHAR(70))
				,CAST([region] AS NVARCHAR(10))
				,CAST([brand_code] AS NVARCHAR(3))
				,[type]
				,CAST([season] AS NVARCHAR(20))
				,CAST([item_id] AS NVARCHAR(40))
				,CAST(ISNULL([description], N'') AS NVARCHAR(300))
				,CAST([price_string] AS NVARCHAR(30))
				,CAST([currency_code] AS NVARCHAR(3))
				,CAST([trade_price] AS DECIMAL(20, 8))
				,CAST([srp_price] AS DECIMAL(20, 8))
			
			FROM [dbo].[preorder_lines];

			CREATE NONCLUSTERED INDEX [IDX_Row_No] ON [Finance].[dbo].[dPreorder Lines] ([Row No]);

			CREATE NONCLUSTERED INDEX [IDX_Preorder_Code] ON [Finance].[dbo].[dPreorder Lines] ([Preorder Code]);

			CREATE NONCLUSTERED INDEX [IDX_Region] ON [Finance].[dbo].[dPreorder Lines] ([Region]);

			CREATE NONCLUSTERED INDEX [IDX_Brand_Code] ON [Finance].[dbo].[dPreorder Lines] ([Brand Code]);

			CREATE NONCLUSTERED INDEX [IDX_Type] ON [Finance].[dbo].[dPreorder Lines] ([Type]);

			CREATE NONCLUSTERED INDEX [IDX_Season] ON [Finance].[dbo].[dPreorder Lines] ([Season]);

			CREATE NONCLUSTERED INDEX [IDX_Item_No] ON [Finance].[dbo].[dPreorder Lines] ([Item No]);

			CREATE NONCLUSTERED INDEX [IDX_Item_Description] ON [Finance].[dbo].[dPreorder Lines] ([Item Description]);

			CREATE NONCLUSTERED INDEX [IDX_Currency] ON [Finance].[dbo].[dPreorder Lines] ([Currency]) INCLUDE (
				 [Price String]
				,[WHS]
				,[SRP]
				);

			CREATE NONCLUSTERED INDEX [IDX_WHS] ON [Finance].[dbo].[dPreorder Lines] ([WHS]) INCLUDE ([SRP]);

			CREATE NONCLUSTERED INDEX [IDX_SRP] ON [Finance].[dbo].[dPreorder Lines] ([SRP]) INCLUDE ([WHS]);

			/*======================================= END TEMPORARY FINANCE COMPATIBILITY SECTION =======================================*/
			DROP TABLE [dbo].[preorder_lines_staging];

			IF @transaction_started = 1
				COMMIT TRANSACTION;

			SELECT @refreshed_rows AS [refreshed_rows];
		
		END TRY

	BEGIN CATCH
		IF @transaction_started = 1
			AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		THROW;
	
	END CATCH;

END;

GO

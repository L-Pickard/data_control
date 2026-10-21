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

-- Required for writes to the index covering persisted computed averages.
SET ARITHABORT ON;
SET ANSI_WARNINGS ON;
SET ANSI_PADDING ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;

DECLARE @transaction_started BIT = 0;

DECLARE @today DATE = CAST(GETDATE() AS DATE);

DECLARE @entity_table TABLE (entity NVARCHAR(20) PRIMARY KEY NOT NULL)

BEGIN TRY
	IF @@TRANCOUNT = 0
	BEGIN
		BEGIN TRANSACTION;

		SET @transaction_started = 1;
	
	END;

	DELETE FROM [dbo].[potential_sell_through];

	DECLARE @pst_id INTEGER

	DECLARE cur CURSOR LOCAL FAST_FORWARD
	FOR

	SELECT [pst_id]
	
	FROM [portal].[pst_reports]

	OPEN cur;

	FETCH NEXT
	
	FROM cur
	
	INTO @pst_id;

	WHILE @@FETCH_STATUS = 0
	BEGIN

		DELETE FROM @entity_table;

		IF (
				SELECT [include_ltd]
				
				FROM [portal].[pst_reports]
				
				WHERE [pst_id] = @pst_id
				) = 1
		BEGIN
			INSERT INTO @entity_table
			
			VALUES ('Shiner Ltd')
		
		END

		IF (
				SELECT [include_bv]
				
				FROM [portal].[pst_reports]
				
				WHERE [pst_id] = @pst_id
				) = 1
		BEGIN
			INSERT INTO @entity_table
			
			VALUES ('Shiner B.V')
		
		END

		IF (
				SELECT [include_llc]
				
				FROM [portal].[pst_reports]
				
				WHERE [pst_id] = @pst_id
				) = 1
		BEGIN
			INSERT INTO @entity_table
			
			VALUES ('Shiner LLC')
		
		END

		INSERT INTO [dbo].[potential_sell_through] (
			 [brand_id]
			,[item_id]
			,[pst_id]
			,[inventory]
			,[po_quantity]
			,[so_quantity]
			,[shipped_last_360_days]
			,[shipped_last_180_days]
			,[shipped_331-360_days]
			,[shipped_301-330_days]
			,[shipped_271-300_days]
			,[shipped_241-270_days]
			,[shipped_211-240_days]
			,[shipped_181-210_days]
			,[shipped_151-180_days]
			,[shipped_121-150_days]
			,[shipped_91-120_days]
			,[shipped_61-90_days]
			,[shipped_31-60_days]
			,[shipped_1-30_days]
			)
		
		SELECT it.[brand_id]
			,it.[item_id]
			,@pst_id AS [pst_id]
			,ISNULL((
					SELECT SUM(iv.[inventory])
					
					FROM [dbo].[inventory] AS iv
					
					WHERE iv.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE iv.[entity] = en.[entity]
							)
					), 0) AS [inventory]
			,ISNULL((
					SELECT SUM(po.[outstanding_quantity])
					
					FROM [dbo].[purchase_orders] AS po
					
					WHERE po.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE po.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'purchase_orders', po.[entity], po.[vendor_id]) = 0
					), 0) AS [po_quantity]
			,ISNULL((
					SELECT SUM(so.[outstanding_quantity])
					
					FROM [dbo].[sales_orders] AS so
					
					WHERE so.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE so.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales_orders', so.[entity], so.[sell_to_customer_id]) = 0
					), 0) AS [so_quantity]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 360, @today)
							AND DATEADD(dd, - 1, @today)
					), 0) AS [shipped_last_360_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 180, @today)
							AND DATEADD(dd, - 1, @today)
					), 0) AS [shipped_last_180_days]
				,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 360, @today)
                        AND DATEADD(dd, - 331, @today)
					), 0) AS [shipped_331-360_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 330, @today)
                        AND DATEADD(dd, - 301, @today)
					), 0) AS [shipped_301-330_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 300, @today)
                        AND DATEADD(dd, - 271, @today)
					), 0) AS [shipped_271-300_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 270, @today)
                        AND DATEADD(dd, - 241, @today)
					), 0) AS [shipped_241-270_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 240, @today)
                        AND DATEADD(dd, - 211, @today)
					), 0) AS [shipped_211-240_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 210, @today)
                        AND DATEADD(dd, - 181, @today)
					), 0) AS [shipped_181-210_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 180, @today)
                        AND DATEADD(dd, - 151, @today)
					), 0) AS [shipped_151-180_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 150, @today)
                        AND DATEADD(dd, - 121, @today)
					), 0) AS [shipped_121-150_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 120, @today)
                        AND DATEADD(dd, - 91, @today)
					), 0) AS [shipped_91-120_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 90, @today)
                        AND DATEADD(dd, - 61, @today)
					), 0) AS [shipped_61-90_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 60, @today)
                        AND DATEADD(dd, - 31, @today)
					), 0) AS [shipped_31-60_days]
			,ISNULL((
					SELECT SUM(sl.[quantity])
					
					FROM [dbo].[sales] AS sl
					
					WHERE sl.[item_id] = it.[item_id]
						AND EXISTS (
							SELECT 1
							
							FROM @entity_table AS en
							
							WHERE sl.[entity] = en.[entity]
							)
						AND dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0
						AND sl.[posting_date] BETWEEN DATEADD(dd, - 30, @today)
                        AND DATEADD(dd, - 1, @today)
					), 0) AS [shipped_1-30_days]
			
		
		FROM (
			SELECT DISTINCT [brand_id]
				,[item_id]
			
			FROM [dbo].[sales]
			
			WHERE [posting_date] BETWEEN DATEADD(dd, - 360, @today)
					AND DATEADD(dd, - 1, @today)
			
			
			UNION
			
			SELECT DISTINCT [brand_id]
				,[item_id]
			
			FROM [dbo].[inventory]
			
			
			UNION
			
			SELECT DISTINCT CAST(LEFT([item_id], 3) AS NVARCHAR(20)) AS [brand_id]
				,[item_id]
			
			FROM [dbo].[purchase_orders]
			
			
			UNION
			
			SELECT DISTINCT [brand_id]
				,[item_id]
			
			FROM [dbo].[sales_orders]
			) AS it

		-- pst update operations end

		FETCH NEXT
		
		FROM cur
		
		INTO @pst_id;
	
	END;

	CLOSE cur;

	DEALLOCATE cur;

	IF @transaction_started = 1
		COMMIT TRANSACTION;

END TRY

BEGIN CATCH
	IF @transaction_started = 1
		AND XACT_STATE() <> 0
		ROLLBACK TRANSACTION;

	THROW;

END CATCH


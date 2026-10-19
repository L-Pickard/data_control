USE [data_control];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE [finance].[build_inventory_cost]
     @dataset_id INT
    ,@rows_json NVARCHAR(MAX)
AS
-- The trusted worker sends validated NAV rows as parameterised JSON. No staging table.
-- Lines, converted costs and header totals are saved atomically; errors roll back everything.
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISNULL(APPLOCK_MODE(N'public', N'inventory_cost_operation', N'Session'),N'NoLock') <> N'Exclusive'
        THROW 50160, 'The inventory worker must hold the operation lock.', 1;
    DECLARE @transaction_started BIT = 0, @rows INT, @expected INT;
    IF ISNULL(ISJSON(@rows_json),0) <> 1 OR LEFT(LTRIM(@rows_json),1) <> N'['
        THROW 50162, 'Dataset rows must be a JSON array.', 1;
    SELECT @expected = COUNT(*) FROM OPENJSON(@rows_json);
    IF @expected = 0
        THROW 50163, 'NAV returned no stock for the as-of date.', 1;
    IF EXISTS (
        SELECT 1 FROM OPENJSON(@rows_json) WITH (
             [entity] NVARCHAR(MAX) '$.entity'
            ,[item_id] NVARCHAR(MAX) '$.item_id'
            ,[location_code] NVARCHAR(MAX) '$.location_code'
            ,[quantity] DECIMAL(38,20) '$.quantity'
            ,[cost] DECIMAL(38,20) '$.cost'
            ,[expected_cost] DECIMAL(38,20) '$.expected_cost'
            ,[first_receipt] DATE '$.first_receipt'
            ,[last_receipt] DATE '$.last_receipt'
        ) AS st
        WHERE NULLIF(LTRIM(RTRIM(st.entity)), N'') IS NULL OR LEN(st.entity) > 20
            OR NULLIF(LTRIM(RTRIM(st.item_id)), N'') IS NULL OR LEN(st.item_id) > 20
            OR st.location_code IS NULL OR LEN(st.location_code)>10
            OR st.quantity IS NULL OR st.quantity <= 0 OR st.cost IS NULL
            OR st.entity NOT IN (N'Shiner Ltd',N'Shiner B.V',N'Shiner LLC')
            OR (st.first_receipt IS NULL AND st.last_receipt IS NOT NULL)
            OR (st.first_receipt IS NOT NULL AND st.last_receipt IS NULL)
            OR st.first_receipt > st.last_receipt
    ) THROW 50163, 'Dataset rows contain invalid keys, amounts or receipt dates.', 1;
    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaction_started = 1;
        END;
        IF NOT EXISTS (
            SELECT 1 FROM [finance].[inventory_cost_headers] WITH (UPDLOCK, HOLDLOCK)
            WHERE dataset_id = @dataset_id AND status = N'loading'
        ) THROW 50161, 'The dataset is not building, so it cannot be saved.', 1;
        IF EXISTS (SELECT 1 FROM OPENJSON(@rows_json) WITH (entity NVARCHAR(20), location_code NVARCHAR(10)) r
            WHERE NOT EXISTS (SELECT 1 FROM finance.inventory_cost_headers h
                JOIN finance.inventory_cost_checks c ON c.check_id=h.check_id
                CROSS APPLY OPENJSON(c.scope_json) WITH (entity NVARCHAR(20), locations NVARCHAR(MAX) AS JSON) sc
                WHERE h.dataset_id=@dataset_id AND sc.entity=r.entity
                    AND (sc.locations IS NULL OR EXISTS (SELECT 1 FROM OPENJSON(sc.locations) l WHERE l.value=r.location_code))))
            THROW 50165, 'Dataset rows are outside the checked entity/location scope.', 1;
		INSERT INTO [finance].[inventory_cost_lines] (
			 [dataset_id]
			,[entity]
			,[item_id]
			,[location_code]
			,[currency_code]
			,[quantity]
			,[cost]
			,[expected_cost]
			,[cost_gbp]
			,[cost_eur]
			,[cost_usd]
			,[first_receipt]
			,[last_receipt]
			)
		SELECT @dataset_id
			,st.[entity]
			,st.[item_id]
			,st.[location_code]
			,en.[currency_code]
			,st.[quantity]
			,st.[cost]
			,ISNULL(st.[expected_cost], 0)
			,CAST(st.[cost] * CASE en.[currency_code]
					WHEN 'GBP'
						THEN 1
					WHEN 'EUR'
						THEN hd.[eur_gbp]
					WHEN 'USD'
						THEN hd.[usd_gbp]
					END AS DECIMAL(38, 20))
			,CAST(st.[cost] * CASE en.[currency_code]
					WHEN 'GBP'
						THEN hd.[gbp_eur]
					WHEN 'EUR'
						THEN 1
					WHEN 'USD'
						THEN hd.[usd_eur]
					END AS DECIMAL(38, 20))
			,CAST(st.[cost] * CASE en.[currency_code]
					WHEN 'GBP'
						THEN hd.[gbp_usd]
					WHEN 'EUR'
						THEN hd.[eur_usd]
					WHEN 'USD'
						THEN 1
					END AS DECIMAL(38, 20))
			,st.[first_receipt]
			,st.[last_receipt]

		FROM OPENJSON(@rows_json) WITH (
             [entity] NVARCHAR(MAX) '$.entity'
            ,[item_id] NVARCHAR(MAX) '$.item_id'
            ,[location_code] NVARCHAR(MAX) '$.location_code'
            ,[quantity] DECIMAL(38,20) '$.quantity'
            ,[cost] DECIMAL(38,20) '$.cost'
            ,[expected_cost] DECIMAL(38,20) '$.expected_cost'
            ,[first_receipt] DATE '$.first_receipt'
            ,[last_receipt] DATE '$.last_receipt'
        ) AS st

		INNER JOIN [dbo].[entities] AS en
			ON en.[entity] = st.[entity]

		CROSS JOIN [finance].[inventory_cost_headers] AS hd

		WHERE hd.[dataset_id] = @dataset_id;

        SET @rows = @@ROWCOUNT;
        IF @rows <> @expected
            THROW 50164, 'Some dataset rows were not saved (unknown company).', 1;

		UPDATE hd

		SET [status] = N'complete'
			,[completed_at] = SYSDATETIME()
			,[line_count] = @rows
			,[total_gbp] = totals.[total_gbp]
			,[total_eur] = totals.[total_eur]
			,[total_usd] = totals.[total_usd]
			,[message] = NULL

		FROM [finance].[inventory_cost_headers] AS hd

		CROSS APPLY (
			SELECT ISNULL(SUM(ln.[cost_gbp]), 0) AS [total_gbp]
				,ISNULL(SUM(ln.[cost_eur]), 0) AS [total_eur]
				,ISNULL(SUM(ln.[cost_usd]), 0) AS [total_usd]

			FROM [finance].[inventory_cost_lines] AS ln

			WHERE ln.[dataset_id] = hd.[dataset_id]
			) AS totals

		WHERE hd.[dataset_id] = @dataset_id;


        IF @transaction_started = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @transaction_started = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

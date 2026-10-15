USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[request_inventory_cost]
	 @check_id INT
	,@description NVARCHAR(200)
	,@created_by_id NVARCHAR(184)
	,@created_by NVARCHAR(256)
	,@cost_adjusted_confirmed BIT
	,@posted_to_gl_confirmed BIT
	,@rate_method NVARCHAR(20)
	,@rates_from DATE = NULL
	,@rates_to DATE = NULL
	,@gbp_eur DECIMAL(38, 20)
	,@gbp_usd DECIMAL(38, 20)
	,@eur_gbp DECIMAL(38, 20)
	,@eur_usd DECIMAL(38, 20)
	,@usd_gbp DECIMAL(38, 20)
	,@usd_eur DECIMAL(38, 20)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     15/10/2026
=================================================================================================================================================
Queues a new inventory cost dataset (finance.inventory_cost header, status 'requested'). Called by the Shiner Reports
portal (Inventory Datasets app) once the person has a passed check and has ticked "Item adjusting cost complete" and
"Item costs posted to G/L". The portal passes the signed-in person's id and name, and the rates it worked out on the
server for the chosen method (latest daily rates or the last four weeks' average, with the dates they cover) or the
rates the person typed (manual; no dates).

The dataset takes its as-of date from the check. The check must be complete and passed (no value entries left to
post to the G/L) and the latest completed check for its date, so a newer result always wins. Receipts not invoiced
and entries not adjusted are warnings only (user decisions, 15 October 2026).

The inventory cost job (scripts/run_inventory_cost.py) then reads NAV into finance.inventory_cost_staging and calls
build_inventory_cost. Returns one row: outcome (ok or refused), message and dataset_id.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @description = LTRIM(RTRIM(ISNULL(@description, N'')));
	SET @created_by_id = LTRIM(RTRIM(ISNULL(@created_by_id, N'')));
	SET @created_by = LTRIM(RTRIM(ISNULL(@created_by, N'')));
	SET @rate_method = LTRIM(RTRIM(ISNULL(@rate_method, N'')));

	IF @created_by_id = N''
		OR @created_by = N''
		THROW 50131, 'The @created_by_id and @created_by parameters cannot be blank.', 1;

	DECLARE @refusal NVARCHAR(400);
	DECLARE @as_of_date DATE;
	DECLARE @status NVARCHAR(20);
	DECLARE @is_passed BIT;
	DECLARE @dataset_id INT;

	SELECT @as_of_date = ck.[as_of_date]
		,@status = ck.[status]
		,@is_passed = ck.[is_passed]

	FROM [finance].[inventory_cost_checks] AS ck

	WHERE ck.[check_id] = @check_id;

	SET @refusal = CASE
			WHEN @description = N''
				THEN N'Enter a description for the dataset.'
			WHEN LEN(@description) > 100
				THEN N'The description can be at most 100 characters.'
			WHEN EXISTS (
					SELECT 1

					FROM [finance].[inventory_cost] AS ic

					WHERE ic.[description] = @description
					)
				THEN N'A dataset with this description already exists. Choose another description.'
			WHEN ISNULL(@cost_adjusted_confirmed, 0) = 0
				OR ISNULL(@posted_to_gl_confirmed, 0) = 0
				THEN N'Confirm that item cost adjustment is complete and item costs are posted to the G/L.'
			WHEN @as_of_date IS NULL
				THEN N'The check could not be found. Run the check again.'
			WHEN @status <> N'complete'
				THEN N'The check has not finished. Wait for its result.'
			WHEN @is_passed = 0
				THEN N'The check did not pass: there are item costs not yet posted to the G/L. Post them in NAV, then run the check again.'
			WHEN EXISTS (
					SELECT 1

					FROM [finance].[inventory_cost_checks] AS newer

					WHERE newer.[as_of_date] = @as_of_date
						AND newer.[status] = N'complete'
						AND newer.[check_id] > @check_id
					)
				THEN N'There is a newer check for this date. Use the latest check.'
			WHEN @rate_method NOT IN (N'latest', N'fourWeeks', N'manual')
				THEN N'Choose an exchange rate method.'
			WHEN @rate_method = N'manual'
				AND (
					@rates_from IS NOT NULL
					OR @rates_to IS NOT NULL
					)
				THEN N'Typed exchange rates have no dates.'
			WHEN @rate_method <> N'manual'
				AND (
					@rates_from IS NULL
					OR @rates_to IS NULL
					OR @rates_from > @rates_to
					)
				THEN N'The exchange rates need the dates they cover.'
			WHEN ISNULL(@gbp_eur, 0) <= 0
				OR ISNULL(@gbp_usd, 0) <= 0
				OR ISNULL(@eur_gbp, 0) <= 0
				OR ISNULL(@eur_usd, 0) <= 0
				OR ISNULL(@usd_gbp, 0) <= 0
				OR ISNULL(@usd_eur, 0) <= 0
				THEN N'Every exchange rate must be more than 0.'
			END;

	IF @refusal IS NOT NULL
	BEGIN
		SELECT N'refused' AS [outcome]
			,@refusal AS [message]
			,CAST(NULL AS INT) AS [dataset_id];

		RETURN;

	END;

	BEGIN TRY
		INSERT INTO [finance].[inventory_cost] (
			 [description]
			,[as_of_date]
			,[check_id]
			,[created_by_id]
			,[created_by]
			,[cost_adjusted_confirmed_at]
			,[posted_to_gl_confirmed_at]
			,[rate_method]
			,[rates_from]
			,[rates_to]
			,[gbp_eur]
			,[gbp_usd]
			,[eur_gbp]
			,[eur_usd]
			,[usd_gbp]
			,[usd_eur]
			)
		VALUES (
			 @description
			,@as_of_date
			,@check_id
			,@created_by_id
			,@created_by
			,SYSDATETIME()
			,SYSDATETIME()
			,@rate_method
			,@rates_from
			,@rates_to
			,@gbp_eur
			,@gbp_usd
			,@eur_gbp
			,@eur_usd
			,@usd_gbp
			,@usd_eur
			);

		SET @dataset_id = CAST(SCOPE_IDENTITY() AS INT);

	END TRY

	BEGIN CATCH
		-- Another request with the same description got in first (UQ_inventory_cost_description).
		IF ERROR_NUMBER() IN (2601, 2627)
		BEGIN
			SELECT N'refused' AS [outcome]
				,N'A dataset with this description already exists. Choose another description.' AS [message]
				,CAST(NULL AS INT) AS [dataset_id];

			RETURN;

		END;

		THROW;

	END CATCH;

	SELECT N'ok' AS [outcome]
		,N'The dataset has been queued. It usually starts within a minute and takes a few minutes.' AS [message]
		,@dataset_id AS [dataset_id];
END;

GO

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
    ,@review_confirmed BIT = 0
    ,@override_unposted BIT = 0
    ,@override_reason NVARCHAR(1000) = NULL
AS
-- Starts one inventory operation. Submissions and the worker share an exclusive lock.
-- No waiting queue: a second submission is refused. Interrupted operations are failed
-- only after acquiring the worker lock, so a live worker is never timed out.

BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 THROW 50120, 'Start inventory operations outside an existing transaction.', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @lock_result INT;
    EXEC @lock_result = sys.sp_getapplock @Resource=N'inventory_cost_operation',
        @LockMode=N'Exclusive', @LockOwner=N'Transaction', @LockTimeout=0;
    IF @lock_result < 0
    BEGIN
        ROLLBACK TRANSACTION;
        SELECT N'refused' AS outcome,N'An inventory operation is already running. Please try again when it finishes.' AS message,
            CAST(NULL AS INT) AS dataset_id;
        RETURN;
    END;
    -- No worker holds the session lock. Running records therefore belonged to an interrupted worker.
    UPDATE finance.inventory_cost_checks
    SET status=N'failed', completed_at=SYSDATETIME(), message=N'Interrupted: the worker stopped. Run the check again.'
    WHERE status=N'running' OR (status=N'requested' AND requested_at < DATEADD(MINUTE,-2,SYSDATETIME()));
    UPDATE finance.inventory_cost_headers
    SET status=N'failed', completed_at=SYSDATETIME(), message=N'Interrupted: the worker stopped. Create the dataset again.'
    WHERE status=N'loading' OR (status=N'requested' AND created_at < DATEADD(MINUTE,-2,SYSDATETIME()));
    IF EXISTS (SELECT 1 FROM finance.inventory_cost_checks WHERE status=N'requested')
        OR EXISTS (SELECT 1 FROM finance.inventory_cost_headers WHERE status=N'requested')
    BEGIN
        COMMIT TRANSACTION;
        SELECT N'refused' AS outcome,N'An inventory operation is starting. Please try again when it finishes.' AS message,
            CAST(NULL AS INT) AS dataset_id;
        RETURN;
    END;


    SET @override_reason = NULLIF(LTRIM(RTRIM(@override_reason)), N'');
    IF ISNULL(@override_unposted,0)=0 SET @override_reason=NULL;
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
    DECLARE @unposted_entries INT;
	DECLARE @dataset_id INT;
	DECLARE @started INT;

	SELECT @as_of_date = ck.[as_of_date]
		,@status = ck.[status]
		,@is_passed = ck.[is_passed]
        ,@unposted_entries = ck.[unposted_entries]

	FROM [finance].[inventory_cost_checks] AS ck

	WHERE ck.[check_id] = @check_id;

	SET @refusal = CASE
			WHEN @description = N''
				THEN N'Enter a description for the dataset.'
			WHEN LEN(@description) > 100
				THEN N'The description can be at most 100 characters.'
			WHEN EXISTS (
					SELECT 1

					FROM [finance].[inventory_cost_headers] AS ic

					WHERE ic.[description] = @description
					)
				THEN N'A dataset with this description already exists. Choose another description.'
			WHEN ISNULL(@review_confirmed,0)=0 AND (ISNULL(@cost_adjusted_confirmed,0)=0 OR ISNULL(@posted_to_gl_confirmed,0)=0)
                THEN N'Confirm that you have reviewed the check results and warnings.'
			WHEN @as_of_date IS NULL
				THEN N'The check could not be found. Run the check again.'
			WHEN @status <> N'complete'
				THEN N'A completed check is required. Failed or unfinished checks cannot be overridden.'
			WHEN @is_passed = 0 AND ISNULL(@override_unposted,0)=0
                THEN N'There are costs not posted to the G/L. Post them and rerun, or explicitly override with a reason.'
            WHEN ISNULL(@override_unposted,0)=1 AND (@is_passed=1 OR ISNULL(@unposted_entries,0)<=0)
                THEN N'Only a completed check with unposted G/L costs can be overridden.'
            WHEN ISNULL(@override_unposted,0)=1 AND (@override_reason IS NULL OR LEN(@override_reason)>500)
                THEN N'Enter an override reason of 1 to 500 characters.'
			WHEN EXISTS (
					SELECT 1

					FROM [finance].[inventory_cost_checks] AS newer

					WHERE newer.[as_of_date] = @as_of_date
						AND newer.[status] = N'complete'
                        AND newer.scope_json = (SELECT scope_json FROM finance.inventory_cost_checks WHERE check_id=@check_id)
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
		IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
		SELECT N'refused' AS [outcome]
			,@refusal AS [message]
			,CAST(NULL AS INT) AS [dataset_id];

		RETURN;

	END;

	BEGIN TRY
		INSERT INTO [finance].[inventory_cost_headers] (
			 [description]
			,[as_of_date]
			,[check_id]
			,[created_by_id]
			,[created_by]
			,[cost_adjusted_confirmed_at]
			,[posted_to_gl_confirmed_at]
			,[reviewed_at]
            ,[override_reason]
            ,[override_at]
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
            ,CASE WHEN @cost_adjusted_confirmed=1 THEN SYSDATETIME() END
            ,CASE WHEN @posted_to_gl_confirmed=1 AND ISNULL(@override_unposted,0)=0 THEN SYSDATETIME() END
            ,SYSDATETIME()
            ,@override_reason
            ,CASE WHEN @override_unposted=1 THEN SYSDATETIME() END
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
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
			IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
		SELECT N'refused' AS [outcome]
				,N'A dataset with this description already exists. Choose another description.' AS [message]
				,CAST(NULL AS INT) AS [dataset_id];

			RETURN;

		END;

		THROW;

	END CATCH;

    IF @override_unposted=1
    BEGIN
        DECLARE @override_log NVARCHAR(MAX)=CONCAT(N'G/L check ',@check_id,N' overridden for dataset ',@dataset_id,N' by ',@created_by,N' (',@created_by_id,N'); ',@unposted_entries,N' unposted entries. Reason: ',@override_reason);
        EXEC dbo.write_db_log @level=N'WARNING',@table=N'inventory_cost',@action=N'override inventory G/L check',@message=@override_log;
    END;
    COMMIT TRANSACTION;
    EXEC @started = [finance].[start_inventory_cost_job];
    IF @started <> 0
    BEGIN
        UPDATE finance.inventory_cost_headers
        SET status=N'failed',completed_at=SYSDATETIME(),message=N'The background job could not start. Please try again.'
        WHERE dataset_id=@dataset_id AND status=N'requested';
        IF @@ROWCOUNT > 0
        BEGIN
            SELECT N'refused' AS outcome,N'The background job could not start. Please try again.' AS message,@dataset_id AS dataset_id;
            RETURN;
        END;
    END;
    SELECT N'ok' AS outcome,N'The dataset has started. It usually takes a few minutes.' AS message,@dataset_id AS dataset_id;
    END TRY
    BEGIN CATCH
        DECLARE @failure NVARCHAR(4000)=ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        UPDATE finance.inventory_cost_headers SET status=N'failed',completed_at=SYSDATETIME(),message=@failure
        WHERE dataset_id=@dataset_id AND status=N'requested';
        THROW;
    END CATCH;
END;
GO

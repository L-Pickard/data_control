USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[request_inventory_cost_check]
	 @as_of_date DATE
	,@requested_by_id NVARCHAR(184)
	,@requested_by NVARCHAR(256)
    ,@scope_json NVARCHAR(MAX) = N'[{"entity":"Shiner Ltd","locations":["BRISTOL"]},{"entity":"Shiner B.V","locations":["3PL"]},{"entity":"Shiner LLC","locations":["POMONA"]}]'
AS
-- Starts one inventory operation. Submissions and the worker share an exclusive lock.
-- No waiting queue: a second submission is refused. Interrupted operations are failed
-- only after acquiring the worker lock, so a live worker is never timed out.

BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 THROW 50120, 'Start inventory operations outside an existing transaction.', 1;

    IF ISJSON(@scope_json) <> 1 OR LEFT(LTRIM(@scope_json),1) <> N'['
        THROW 50122, 'Choose a valid entity and location scope.', 1;
    IF (SELECT COUNT(*) FROM OPENJSON(@scope_json)) NOT BETWEEN 1 AND 3
        OR EXISTS (SELECT 1 FROM OPENJSON(@scope_json) WITH (entity NVARCHAR(MAX), locations NVARCHAR(MAX) AS JSON) s
            WHERE s.entity IS NULL OR s.entity NOT IN (N'Shiner Ltd',N'Shiner B.V',N'Shiner LLC')
                OR (s.locations IS NOT NULL AND (LEFT(LTRIM(s.locations),1)<>N'[' OR (SELECT COUNT(*) FROM OPENJSON(s.locations)) NOT BETWEEN 1 AND 100
                    OR EXISTS (SELECT 1 FROM OPENJSON(s.locations) l WHERE l.type<>1 OR LEN(l.value)>10))))
        OR (SELECT COUNT(DISTINCT entity) FROM OPENJSON(@scope_json) WITH (entity NVARCHAR(20))) <> (SELECT COUNT(*) FROM OPENJSON(@scope_json))
        THROW 50122, 'Choose a valid entity and location scope.', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @lock_result INT;
    EXEC @lock_result = sys.sp_getapplock @Resource=N'inventory_cost_operation',
        @LockMode=N'Exclusive', @LockOwner=N'Transaction', @LockTimeout=0;
    IF @lock_result < 0
    BEGIN
        ROLLBACK TRANSACTION;
        SELECT N'refused' AS outcome,N'An inventory operation is already running. Please try again when it finishes.' AS message,
            CAST(NULL AS INT) AS check_id;
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
            CAST(NULL AS INT) AS check_id;
        RETURN;
    END;


	SET @requested_by_id = LTRIM(RTRIM(ISNULL(@requested_by_id, N'')));
	SET @requested_by = LTRIM(RTRIM(ISNULL(@requested_by, N'')));

	IF @requested_by_id = N''
		OR @requested_by = N''
		THROW 50121, 'The @requested_by_id and @requested_by parameters cannot be blank.', 1;

	DECLARE @check_id INT;
	DECLARE @started INT;
	DECLARE @purged INT;
	DECLARE @purge_message NVARCHAR(400);

	DELETE ck

	FROM [finance].[inventory_cost_checks] AS ck

	WHERE ck.[status] IN (N'complete', N'failed')
		AND ck.[completed_at] < DATEADD(DAY, - 30, SYSDATETIME())
		AND NOT EXISTS (
			SELECT 1

			FROM [finance].[inventory_cost_headers] AS ic

			WHERE ic.[check_id] = ck.[check_id]
			);

	SET @purged = @@ROWCOUNT;

	IF @purged > 0
	BEGIN
		SET @purge_message = CONCAT(@purged, N' inventory cost checks finished more than 30 days ago and not used by any dataset were removed with their warning lists.');

		EXEC [dbo].[write_db_log]
			 @level = N'INFO'
			,@table = N'inventory_cost'
			,@rows = @purged
			,@action = N'remove old inventory cost checks'
			,@message = @purge_message;

	END;

	IF @as_of_date IS NULL
		OR @as_of_date > CAST(SYSDATETIME() AS DATE)
	BEGIN
		IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
		SELECT N'refused' AS [outcome]
			,N'Choose an as-of date that is today or earlier.' AS [message]
			,CAST(NULL AS INT) AS [check_id];

		RETURN;

	END;

	INSERT INTO [finance].[inventory_cost_checks] (
		 [as_of_date]
        ,[scope_json]
		,[requested_by_id]
		,[requested_by]
		)
	VALUES (
		 @as_of_date
        ,@scope_json
		,@requested_by_id
		,@requested_by
		);

	SET @check_id = CAST(SCOPE_IDENTITY() AS INT);

    COMMIT TRANSACTION;
    EXEC @started = [finance].[start_inventory_cost_job];
    IF @started <> 0
    BEGIN
        UPDATE finance.inventory_cost_checks
        SET status=N'failed',completed_at=SYSDATETIME(),message=N'The background job could not start. Please try again.'
        WHERE check_id=@check_id AND status=N'requested';
        IF @@ROWCOUNT > 0
        BEGIN
            SELECT N'refused' AS outcome,N'The background job could not start. Please try again.' AS message,@check_id AS check_id;
            RETURN;
        END;
    END;
    SELECT N'ok' AS outcome,N'The check has started. It usually takes a few minutes.' AS message,@check_id AS check_id;
    END TRY
    BEGIN CATCH
        DECLARE @failure NVARCHAR(4000)=ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        UPDATE finance.inventory_cost_checks SET status=N'failed',completed_at=SYSDATETIME(),message=@failure
        WHERE check_id=@check_id AND status=N'requested';
        THROW;
    END CATCH;
END;
GO

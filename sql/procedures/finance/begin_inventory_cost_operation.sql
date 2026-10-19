USE [data_control];
GO
CREATE OR ALTER PROCEDURE [finance].[begin_inventory_cost_operation]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISNULL(APPLOCK_MODE(N'public', N'inventory_cost_operation', N'Session'), N'NoLock') <> N'Exclusive'
        THROW 50140, 'The inventory worker must hold the operation lock.', 1;
    DECLARE @count INT, @kind NVARCHAR(10), @id INT, @as_of DATE, @scope NVARCHAR(MAX);
    SELECT @count=COUNT(*) FROM (
        SELECT check_id FROM finance.inventory_cost_checks WHERE status=N'requested'
        UNION ALL
        SELECT dataset_id FROM finance.inventory_cost_headers WHERE status=N'requested'
    ) AS pending;
    IF @count > 1 THROW 50141, 'Multiple pending inventory operations exist. Resolve them before continuing.', 1;
    IF @count = 0
    BEGIN
        SELECT CAST(NULL AS NVARCHAR(10)) AS request_kind, CAST(NULL AS INT) AS request_id, CAST(NULL AS DATE) AS as_of_date, CAST(NULL AS NVARCHAR(MAX)) AS scope_json WHERE 1=0;
        RETURN;
    END;
    SELECT @kind=N'check', @id=check_id, @as_of=as_of_date
    FROM finance.inventory_cost_checks WHERE status=N'requested';
    IF @id IS NULL
        SELECT @kind=N'dataset', @id=dataset_id, @as_of=as_of_date
        FROM finance.inventory_cost_headers WHERE status=N'requested';
    IF @kind=N'check'
        UPDATE finance.inventory_cost_checks SET status=N'running',started_at=SYSDATETIME() WHERE check_id=@id;
    ELSE
        UPDATE finance.inventory_cost_headers SET status=N'loading',started_at=SYSDATETIME() WHERE dataset_id=@id;
    SELECT @scope=scope_json FROM finance.inventory_cost_checks
    WHERE check_id=CASE WHEN @kind=N'check' THEN @id ELSE (SELECT check_id FROM finance.inventory_cost_headers WHERE dataset_id=@id) END;
    SELECT @kind AS request_kind,@id AS request_id,@as_of AS as_of_date,@scope AS scope_json;
END;
GO

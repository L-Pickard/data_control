USE [data_control];
SET NOCOUNT ON;
-- Exercise the deployed function body with controlled timestamps.
DECLARE @definition NVARCHAR(MAX)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.fnc_calculate_sales_clear_date'));
IF @definition IS NULL THROW 52201,'Sales clear date function is missing.',1;
DECLARE @body NVARCHAR(MAX)=SUBSTRING(@definition,CHARINDEX('BEGIN',@definition),LEN(@definition));
SET @body=REPLACE(REPLACE(@body,'GETDATE()','@test_datetime'),'RETURN @return_date;','SET @actual = @return_date;');
DECLARE @cases TABLE (test_datetime DATETIME, expected DATE);
INSERT @cases VALUES
('2026-09-10T07:00:00','20260903'),
('2026-09-10T05:00:00','20260801'),
('2026-09-14T05:00:00','20240430'),
('2026-04-27T05:00:00','20230430'),
('2029-04-30T05:00:00','20270430'),
('2026-09-14T06:00:00','20240430'),
('2026-09-14T06:00:00.003','20260907'),
('2026-01-01T05:00:00','20251201'),
('2024-03-04T07:00:00','20240226');
DECLARE @test_datetime DATETIME, @expected DATE, @actual DATE, @checked INT=0;
-- Exercise a non-English session and a different weekday numbering scheme.
SET LANGUAGE French;
SET DATEFIRST 3;
DECLARE cases CURSOR LOCAL FAST_FORWARD FOR SELECT test_datetime,expected FROM @cases;
OPEN cases;
FETCH NEXT FROM cases INTO @test_datetime,@expected;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @actual=NULL;
    EXEC sys.sp_executesql @body,N'@test_datetime DATETIME,@actual DATE OUTPUT',@test_datetime,@actual OUTPUT;
    IF @actual IS NULL OR @actual<>@expected THROW 52200,'Sales clear date boundary test failed.',1;
    SET @checked+=1;
    FETCH NEXT FROM cases INTO @test_datetime,@expected;
END;
CLOSE cases;
DEALLOCATE cases;
SELECT @checked AS boundary_tests_passed;


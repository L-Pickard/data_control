USE [data_control];
GO
CREATE OR ALTER FUNCTION dbo.fnc_is_pst_exclusion
(
     @pst_id INT
    ,@target_table NVARCHAR(30)
    ,@entity NVARCHAR(20)
    ,@party_id NVARCHAR(20)
)
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN EXISTS
    (
        SELECT 1 FROM dbo.exclusions
        WHERE rule_scope = N'pst' AND pst_id = @pst_id
            AND target_table = @target_table AND entity = @entity AND id = @party_id
    ) THEN 1 ELSE 0 END;
END;
GO

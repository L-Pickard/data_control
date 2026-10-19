-- Run inside an OUTER transaction after the migration, then roll back.
-- Exercises global snapshots/deletes against colliding PST rules without retaining changes.
SET XACT_ABORT ON;
IF @@TRANCOUNT=0 THROW 50220, 'This check requires an outer rollback transaction.', 1;
IF (SELECT COUNT(*) FROM dbo.exclusions WHERE rule_scope=N'pst' AND pst_id=1)<>76
    THROW 50221, 'Expected 76 PST rules.', 1;
IF dbo.fnc_is_pst_exclusion(1,N'sales_orders',N'Shiner Ltd',N'CU109506')<>1
 OR dbo.fnc_is_pst_exclusion(1,N'sales',N'Shiner Ltd',N'CU109506')<>0
 OR dbo.fnc_is_pst_exclusion(2,N'sales_orders',N'Shiner Ltd',N'CU109506')<>0
 OR dbo.fnc_is_pst_exclusion(1,N'sales_orders',N'Shiner LLC',N'CU109506')<>0
    THROW 50222, 'PST report/table/entity boundaries failed.', 1;
-- Global functions must agree with global rules only, including keys appearing solely in PST rules.
IF EXISTS
(
    SELECT 1 FROM dbo.exclusions ex
    WHERE dbo.fnc_is_customer_exclusion(ex.entity,ex.id,ex.brand_id) <>
        CASE WHEN EXISTS (SELECT 1 FROM dbo.exclusions g WHERE g.rule_scope=N'global'
            AND g.entity=ex.entity AND g.id=ex.id AND g.[type]=N'exclusion' AND g.table_name=N'customers'
            AND (g.brand_id=N'' OR g.brand_id=ex.brand_id)) THEN 1 ELSE 0 END
    OR dbo.fnc_is_customer_intercompany(ex.entity,ex.id) <>
        CASE WHEN EXISTS (SELECT 1 FROM dbo.exclusions g WHERE g.rule_scope=N'global'
            AND g.entity=ex.entity AND g.id=ex.id AND g.[type]=N'intercompany' AND g.table_name=N'customers'
            AND g.brand_id=N'') THEN 1 ELSE 0 END
    OR dbo.fnc_is_vendor_exclusion(ex.entity,ex.id) <>
        CASE WHEN EXISTS (SELECT 1 FROM dbo.exclusions g WHERE g.rule_scope=N'global'
            AND g.entity=ex.entity AND g.id=ex.id AND g.[type]=N'exclusion' AND g.table_name=N'vendors'
            AND g.brand_id=N'') THEN 1 ELSE 0 END
    OR dbo.fnc_is_vendor_intercompany(ex.entity,ex.id) <>
        CASE WHEN EXISTS (SELECT 1 FROM dbo.exclusions g WHERE g.rule_scope=N'global'
            AND g.entity=ex.entity AND g.id=ex.id AND g.[type]=N'intercompany' AND g.table_name=N'vendors'
            AND g.brand_id=N'') THEN 1 ELSE 0 END
)
    THROW 50223, 'Global flags changed scope.', 1;
DECLARE @snapshot_id INT;
DECLARE @global_count INT=(SELECT COUNT(*) FROM dbo.exclusions WHERE rule_scope=N'global');
EXEC dbo.save_margin_rule_snapshot @taken_by=N'Codex migration rollback test',
    @return_row=0, @snapshot_id=@snapshot_id OUTPUT;
IF (SELECT COUNT(*) FROM dbo.margin_rule_snapshot_exclusions WHERE snapshot_id=@snapshot_id)<>@global_count
    THROW 50224, 'Global snapshot included PST rules.', 1;
EXEC dbo.delete_exclusion_rule @entity=N'Shiner Ltd', @type=N'exclusion', @table_name=N'customers',
    @id=N'CU110025', @brand_id=N'', @changed_by=N'Codex migration rollback test';
IF dbo.fnc_is_pst_exclusion(1,N'sales',N'Shiner Ltd',N'CU110025')<>1
 OR dbo.fnc_is_customer_exclusion(N'Shiner Ltd',N'CU110025',N'')<>0
    THROW 50225, 'Global delete affected a PST rule or failed.', 1;
EXEC dbo.add_exclusion_rule @entity=N'Shiner Ltd', @type=N'exclusion', @table_name=N'customers',
    @id=N'CU110025', @brand_id=N'', @changed_by=N'Codex migration rollback test';
IF dbo.fnc_is_customer_exclusion(N'Shiner Ltd',N'CU110025',N'')<>1
    THROW 50226, 'Legacy add failed with a colliding PST rule.', 1;
EXEC dbo.restore_margin_rule_snapshot @snapshot_id=@snapshot_id, @restored_by=N'Codex migration rollback test';
IF (SELECT COUNT(*) FROM dbo.exclusions WHERE rule_scope=N'pst' AND pst_id=1)<>76
 OR (SELECT COUNT(*) FROM dbo.exclusions WHERE rule_scope=N'global')<>@global_count
    THROW 50227, 'Global restore changed PST rules or failed.', 1;
SELECT N'passed' AS scoped_exclusions_checks;

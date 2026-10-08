USE data_control;
-- Check all 66 customer/brand combinations and preservation of whole-customer rules.
IF EXISTS (
    SELECT 1 FROM dbo.entities AS en
    CROSS JOIN (VALUES (N'CU100487'), (N'CU108312')) AS cu(id)
    CROSS JOIN (VALUES (N'BSC'), (N'BUU'), (N'CRE'), (N'KRX'), (N'MOB'),
                       (N'OJW'), (N'RIC'), (N'SLM'), (N'SCR'), (N'IND'), (N'NHS')) AS br(id)
    WHERE dbo.fnc_is_customer_exclusion(en.entity, cu.id, br.id) <> 1
) THROW 51000, 'A customer-brand rule did not match.', 1;
IF EXISTS (
    SELECT 1 FROM dbo.exclusions AS ex
    WHERE ex.[type] = N'exclusion' AND ex.table_name = N'customers' AND ex.brand_id = N''
      AND (dbo.fnc_is_customer_exclusion(ex.entity, ex.id, N'__OTHER__') <> 1
           OR dbo.fnc_is_customer_exclusion(ex.entity, ex.id, NULL) <> 1)
) THROW 51000, 'An existing whole-customer rule failed.', 1;
IF EXISTS (
    SELECT 1 FROM dbo.entities AS en
    CROSS JOIN (VALUES (N'CU100487'), (N'CU108312')) AS cu(id)
    WHERE dbo.fnc_is_customer_exclusion(en.entity, cu.id, N'__OTHER__') <>
        CASE WHEN EXISTS (SELECT 1 FROM dbo.exclusions AS ex
            WHERE ex.entity=en.entity AND ex.[type]=N'exclusion'
              AND ex.table_name=N'customers' AND ex.id=cu.id AND ex.brand_id=N'') THEN 1 ELSE 0 END
       OR dbo.fnc_is_customer_exclusion(en.entity, N'__OTHER_CUSTOMER__', N'BSC') <> 0
) THROW 51000, 'The brand rules excluded an unrelated combination.', 1;
IF EXISTS (
    SELECT 1 FROM dbo.sales
    WHERE customer_id IN (N'CU100487', N'CU108312')
      AND exclusion <> dbo.fnc_is_customer_exclusion(entity, customer_id, brand_id)
) THROW 51000, 'Existing sales flags do not match the new rules.', 1;
IF EXISTS (
    SELECT 1 FROM dbo.sales_orders
    WHERE sell_to_customer_id IN (N'CU100487', N'CU108312')
      AND exclusion <> dbo.fnc_is_customer_exclusion(entity, sell_to_customer_id, brand_id)
) THROW 51000, 'Sales order flags do not match the new rules.', 1;
SELECT N'Passed' AS brand_exclusion_validation;

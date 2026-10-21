USE data_control;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.update_pst_table
AS
/* Refresh all reports atomically. Order document type 1 = Order; sales line type 2 = Item.
   Purchase loaders populate item_id only for item lines. Whole-order B.V/Ltd matching
   follows the Finance example; Ltd matches are independent of dates/report exclusions.
   Persisted averages are computed by the result table. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET ARITHABORT ON;
    SET ANSI_WARNINGS ON;
    SET ANSI_PADDING ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET NUMERIC_ROUNDABORT OFF;
    DECLARE @transaction_started bit=0,@lock int;
    DECLARE @today date=CAST(GETDATE() AS date);
    DECLARE @pst_id integer,@exclude_bv_sales bit,@exclude_bv_sales_orders bit;
    DECLARE @entity_table TABLE(entity nvarchar(20) NOT NULL PRIMARY KEY);
    BEGIN TRY
        IF @@TRANCOUNT=0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaction_started=1;
        END;
        EXEC @lock=sys.sp_getapplock @Resource=N'dbo.update_pst_table',
            @LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=0;
        IF @lock<0 THROW 50800,'A PST refresh is already running.',1;
        -- The editor takes this resource exclusively; freeze definitions for this build.
        EXEC @lock=sys.sp_getapplock @Resource=N'portal.pst-report-edit',
            @LockMode=N'Shared',@LockOwner=N'Transaction',@LockTimeout=5000;
        IF @lock<0 THROW 50801,'PST definitions are being edited. Try the refresh again.',1;
        SELECT pst_id,include_ltd,include_bv,include_llc,exclude_bv_sales,exclude_bv_sales_orders
        INTO #reports FROM portal.pst_reports WITH(HOLDLOCK);
        CREATE UNIQUE CLUSTERED INDEX IX_reports ON #reports(pst_id);
        SELECT DISTINCT pst_id,target_table,entity,id INTO #rules
        FROM dbo.exclusions WITH(HOLDLOCK) WHERE rule_scope=N'pst';
        CREATE UNIQUE CLUSTERED INDEX IX_rules ON #rules(pst_id,target_table,entity,id);
        -- Cache whole-order matches once for all reports that enable B.V suppression.
        -- Keep the original all-history match for shipped orders.
        SELECT DISTINCT sl.order_no INTO #ltd_shipped_orders FROM dbo.sales AS sl
        WHERE sl.entity=N'Shiner Ltd' AND NULLIF(LTRIM(RTRIM(sl.order_no)),N'') IS NOT NULL
            AND EXISTS(SELECT 1 FROM #reports WHERE include_bv=1 AND exclude_bv_sales=1);
        CREATE UNIQUE CLUSTERED INDEX IX_ltd_shipped_orders ON #ltd_shipped_orders(order_no);
        SELECT DISTINCT so.document_no INTO #ltd_open_orders FROM dbo.sales_orders AS so
        WHERE so.entity=N'Shiner Ltd' AND so.document_type=1
            AND NULLIF(LTRIM(RTRIM(so.document_no)),N'') IS NOT NULL
            AND EXISTS(SELECT 1 FROM #reports WHERE include_bv=1 AND exclude_bv_sales_orders=1);
        CREATE UNIQUE CLUSTERED INDEX IX_ltd_open_orders ON #ltd_open_orders(document_no);
        -- Failure rolls back both this delete and every insert, preserving previous results.
        DELETE FROM dbo.potential_sell_through;
        DECLARE reports CURSOR LOCAL FAST_FORWARD FOR
            SELECT pst_id,exclude_bv_sales,exclude_bv_sales_orders FROM #reports ORDER BY pst_id;
        OPEN reports;
        FETCH NEXT FROM reports INTO @pst_id,@exclude_bv_sales,@exclude_bv_sales_orders;
        WHILE @@FETCH_STATUS=0
        BEGIN
            DELETE FROM @entity_table;
            INSERT @entity_table(entity)
            SELECT choice.entity FROM #reports AS rp
            CROSS APPLY(VALUES(N'Shiner Ltd',rp.include_ltd),(N'Shiner B.V',rp.include_bv),
                (N'Shiner LLC',rp.include_llc)) AS choice(entity,included)
            WHERE rp.pst_id=@pst_id AND choice.included=1;
            -- One aggregation per source/report; every shipped measure has identical filters.
            SELECT sl.item_id,
                SUM(sl.quantity) AS shipped_last_360_days,
                SUM(CASE WHEN sl.posting_date>=DATEADD(day,-180,@today) THEN sl.quantity ELSE 0 END) AS shipped_last_180_days,
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-360,@today) AND DATEADD(day,-331,@today) THEN sl.quantity ELSE 0 END) AS [shipped_331-360_days],
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-330,@today) AND DATEADD(day,-301,@today) THEN sl.quantity ELSE 0 END) AS [shipped_301-330_days],
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-300,@today) AND DATEADD(day,-271,@today) THEN sl.quantity ELSE 0 END) AS [shipped_271-300_days],
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-270,@today) AND DATEADD(day,-241,@today) THEN sl.quantity ELSE 0 END) AS [shipped_241-270_days],
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-240,@today) AND DATEADD(day,-211,@today) THEN sl.quantity ELSE 0 END) AS [shipped_211-240_days],
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-210,@today) AND DATEADD(day,-181,@today) THEN sl.quantity ELSE 0 END) AS [shipped_181-210_days],
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-180,@today) AND DATEADD(day,-151,@today) THEN sl.quantity ELSE 0 END) AS [shipped_151-180_days],
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-150,@today) AND DATEADD(day,-121,@today) THEN sl.quantity ELSE 0 END) AS [shipped_121-150_days],
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-120,@today) AND DATEADD(day,-91,@today) THEN sl.quantity ELSE 0 END) AS [shipped_91-120_days],
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-90,@today) AND DATEADD(day,-61,@today) THEN sl.quantity ELSE 0 END) AS [shipped_61-90_days],
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-60,@today) AND DATEADD(day,-31,@today) THEN sl.quantity ELSE 0 END) AS [shipped_31-60_days],
                SUM(CASE WHEN sl.posting_date BETWEEN DATEADD(day,-30,@today) AND DATEADD(day,-1,@today) THEN sl.quantity ELSE 0 END) AS [shipped_1-30_days]
            INTO #shipped FROM dbo.sales AS sl
            INNER JOIN @entity_table AS en ON en.entity=sl.entity
            WHERE sl.posting_date BETWEEN DATEADD(day,-360,@today) AND DATEADD(day,-1,@today)
                AND NULLIF(sl.item_id,N'') IS NOT NULL
                AND NOT EXISTS(SELECT 1 FROM #rules AS ex WHERE ex.pst_id=@pst_id
                    AND ex.target_table=N'sales' AND ex.entity=sl.entity AND ex.id=sl.customer_id)
                AND(@exclude_bv_sales=0 OR sl.entity<>N'Shiner B.V'
                    OR NULLIF(LTRIM(RTRIM(sl.order_no)),N'') IS NULL
                    OR NOT EXISTS(SELECT 1 FROM #ltd_shipped_orders AS ltd WHERE ltd.order_no=sl.order_no))
            GROUP BY sl.item_id;
            CREATE UNIQUE CLUSTERED INDEX IX_shipped ON #shipped(item_id);
            SELECT iv.item_id,SUM(iv.inventory) AS quantity INTO #stock FROM dbo.inventory AS iv
            INNER JOIN @entity_table AS en ON en.entity=iv.entity
            WHERE NULLIF(iv.item_id,N'') IS NOT NULL GROUP BY iv.item_id;
            CREATE UNIQUE CLUSTERED INDEX IX_stock ON #stock(item_id);
            SELECT po.item_id,SUM(po.outstanding_quantity) AS quantity INTO #purchases FROM dbo.purchase_orders AS po
            INNER JOIN @entity_table AS en ON en.entity=po.entity
            WHERE po.document_type=1 AND NULLIF(po.item_id,N'') IS NOT NULL
                AND NOT EXISTS(SELECT 1 FROM #rules AS ex WHERE ex.pst_id=@pst_id
                    AND ex.target_table=N'purchase_orders' AND ex.entity=po.entity AND ex.id=po.vendor_id)
            GROUP BY po.item_id;
            CREATE UNIQUE CLUSTERED INDEX IX_purchases ON #purchases(item_id);
            SELECT so.item_id,SUM(so.outstanding_quantity) AS quantity INTO #orders FROM dbo.sales_orders AS so
            INNER JOIN @entity_table AS en ON en.entity=so.entity
            WHERE so.document_type=1 AND so.line_type=2 AND NULLIF(so.item_id,N'') IS NOT NULL
                AND NOT EXISTS(SELECT 1 FROM #rules AS ex WHERE ex.pst_id=@pst_id
                    AND ex.target_table=N'sales_orders' AND ex.entity=so.entity AND ex.id=so.sell_to_customer_id)
                AND(@exclude_bv_sales_orders=0 OR so.entity<>N'Shiner B.V'
                    OR NULLIF(LTRIM(RTRIM(so.document_no)),N'') IS NULL
                    OR NOT EXISTS(SELECT 1 FROM #ltd_open_orders AS ltd WHERE ltd.document_no=so.document_no))
            GROUP BY so.item_id;
            CREATE UNIQUE CLUSTERED INDEX IX_orders ON #orders(item_id);
            ;WITH active_items AS(
                SELECT item_id FROM #shipped UNION SELECT item_id FROM #stock
                UNION SELECT item_id FROM #purchases UNION SELECT item_id FROM #orders
            )
            INSERT dbo.potential_sell_through(brand_id,item_id,pst_id,inventory,po_quantity,so_quantity,
                shipped_last_360_days,shipped_last_180_days,
                [shipped_331-360_days],[shipped_301-330_days],[shipped_271-300_days],[shipped_241-270_days],[shipped_211-240_days],[shipped_181-210_days],[shipped_151-180_days],[shipped_121-150_days],[shipped_91-120_days],[shipped_61-90_days],[shipped_31-60_days],[shipped_1-30_days]
            )
            SELECT it.brand_id,it.item_id,@pst_id,ISNULL(iv.quantity,0),ISNULL(po.quantity,0),ISNULL(so.quantity,0),
                ISNULL(sl.shipped_last_360_days,0),ISNULL(sl.shipped_last_180_days,0),
                ISNULL(sl.[shipped_331-360_days],0),ISNULL(sl.[shipped_301-330_days],0),ISNULL(sl.[shipped_271-300_days],0),ISNULL(sl.[shipped_241-270_days],0),ISNULL(sl.[shipped_211-240_days],0),ISNULL(sl.[shipped_181-210_days],0),ISNULL(sl.[shipped_151-180_days],0),ISNULL(sl.[shipped_121-150_days],0),ISNULL(sl.[shipped_91-120_days],0),ISNULL(sl.[shipped_61-90_days],0),ISNULL(sl.[shipped_31-60_days],0),ISNULL(sl.[shipped_1-30_days],0)
            FROM active_items AS a
            INNER JOIN dbo.items AS it ON it.item_id=a.item_id
            INNER JOIN dbo.brands AS br ON br.brand_id=it.brand_id
            LEFT JOIN #stock AS iv ON iv.item_id=a.item_id
            LEFT JOIN #purchases AS po ON po.item_id=a.item_id
            LEFT JOIN #orders AS so ON so.item_id=a.item_id
            LEFT JOIN #shipped AS sl ON sl.item_id=a.item_id;
            DROP TABLE #shipped,#stock,#purchases,#orders;
            FETCH NEXT FROM reports INTO @pst_id,@exclude_bv_sales,@exclude_bv_sales_orders;
        END;
        CLOSE reports;
        DEALLOCATE reports;
        UPDATE rp SET last_updated=SYSUTCDATETIME()
        FROM portal.pst_reports AS rp INNER JOIN #reports AS built ON built.pst_id=rp.pst_id;
        IF @transaction_started=1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local','reports')>=0 CLOSE reports;
        IF CURSOR_STATUS('local','reports')>=-1 DEALLOCATE reports;
        IF @transaction_started=1 AND XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

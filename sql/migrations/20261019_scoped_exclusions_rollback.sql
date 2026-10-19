-- Explicit rollback for the 19 October migration. Review before executing.
-- Removes only the original 76 PST rules and their report, then restores the old schema/modules.
-- Refuses if any report rules have been added or edited. Global edits are preserved.
USE data_control;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 5000;
BEGIN TRANSACTION;
DECLARE @seed TABLE (id NVARCHAR(20), entity NVARCHAR(20), target_table NVARCHAR(30));
INSERT @seed VALUES
(N'CU109506',N'Shiner Ltd',N'sales_orders'),
(N'CU110025',N'Shiner Ltd',N'sales_orders'),
(N'CU110025',N'Shiner LLC',N'sales_orders'),
(N'CU110036',N'Shiner LLC',N'sales_orders'),
(N'CU110040',N'Shiner LLC',N'sales_orders'),
(N'CU110083',N'Shiner LLC',N'sales_orders'),
(N'UC000340',N'Shiner B.V',N'sales_orders'),
(N'UC000650',N'Shiner B.V',N'sales_orders'),
(N'UC000653',N'Shiner B.V',N'sales_orders'),
(N'CU103500',N'Shiner Ltd',N'sales_orders'),
(N'CU103500',N'Shiner LLC',N'sales_orders'),
(N'CU109221',N'Shiner Ltd',N'sales_orders'),
(N'CU109221',N'Shiner LLC',N'sales_orders'),
(N'CU109441',N'Shiner Ltd',N'sales_orders'),
(N'CU109441',N'Shiner LLC',N'sales_orders'),
(N'CU109444',N'Shiner Ltd',N'sales_orders'),
(N'CU109444',N'Shiner LLC',N'sales_orders'),
(N'CU109525',N'Shiner Ltd',N'sales_orders'),
(N'CU109525',N'Shiner LLC',N'sales_orders'),
(N'CU110077',N'Shiner Ltd',N'sales_orders'),
(N'CU110077',N'Shiner LLC',N'sales_orders'),
(N'CU110744',N'Shiner LLC',N'sales_orders'),
(N'UC000458',N'Shiner B.V',N'sales_orders'),
(N'CU110025',N'Shiner Ltd',N'sales'),
(N'CU110025',N'Shiner B.V',N'sales'),
(N'CU110036',N'Shiner Ltd',N'sales'),
(N'CU110040',N'Shiner Ltd',N'sales'),
(N'CU110083',N'Shiner Ltd',N'sales'),
(N'CU109506',N'Shiner B.V',N'sales'),
(N'UC000650',N'Shiner LLC',N'sales'),
(N'UC000653',N'Shiner LLC',N'sales'),
(N'UC000340',N'Shiner LLC',N'sales'),
(N'CU103500',N'Shiner Ltd',N'sales'),
(N'CU103500',N'Shiner B.V',N'sales'),
(N'CU109221',N'Shiner Ltd',N'sales'),
(N'CU109221',N'Shiner B.V',N'sales'),
(N'CU109441',N'Shiner Ltd',N'sales'),
(N'CU109441',N'Shiner B.V',N'sales'),
(N'CU109444',N'Shiner Ltd',N'sales'),
(N'CU109444',N'Shiner B.V',N'sales'),
(N'CU109525',N'Shiner Ltd',N'sales'),
(N'CU109525',N'Shiner B.V',N'sales'),
(N'CU110077',N'Shiner Ltd',N'sales'),
(N'CU110077',N'Shiner B.V',N'sales'),
(N'CU110744',N'Shiner Ltd',N'sales'),
(N'UC000458',N'Shiner LLC',N'sales'),
(N'UV000199',N'Shiner Ltd',N'purchase_orders'),
(N'UV000199',N'Shiner B.V',N'purchase_orders'),
(N'UV000199',N'Shiner LLC',N'purchase_orders'),
(N'UV000200',N'Shiner Ltd',N'purchase_orders'),
(N'UV000200',N'Shiner B.V',N'purchase_orders'),
(N'UV000200',N'Shiner LLC',N'purchase_orders'),
(N'VE100194',N'Shiner Ltd',N'purchase_orders'),
(N'VE100194',N'Shiner B.V',N'purchase_orders'),
(N'VE100194',N'Shiner LLC',N'purchase_orders'),
(N'VE100890',N'Shiner Ltd',N'purchase_orders'),
(N'VE100890',N'Shiner B.V',N'purchase_orders'),
(N'VE100890',N'Shiner LLC',N'purchase_orders'),
(N'UV000081',N'Shiner Ltd',N'purchase_orders'),
(N'UV000081',N'Shiner B.V',N'purchase_orders'),
(N'UV000081',N'Shiner LLC',N'purchase_orders'),
(N'UV000195',N'Shiner Ltd',N'purchase_orders'),
(N'UV000195',N'Shiner B.V',N'purchase_orders'),
(N'UV000195',N'Shiner LLC',N'purchase_orders'),
(N'VE100520',N'Shiner Ltd',N'purchase_orders'),
(N'VE100520',N'Shiner B.V',N'purchase_orders'),
(N'VE100520',N'Shiner LLC',N'purchase_orders'),
(N'VE100927',N'Shiner Ltd',N'purchase_orders'),
(N'VE100927',N'Shiner B.V',N'purchase_orders'),
(N'VE100927',N'Shiner LLC',N'purchase_orders'),
(N'VE100934',N'Shiner Ltd',N'purchase_orders'),
(N'VE100934',N'Shiner B.V',N'purchase_orders'),
(N'VE100934',N'Shiner LLC',N'purchase_orders'),
(N'VE100952',N'Shiner Ltd',N'purchase_orders'),
(N'VE100952',N'Shiner B.V',N'purchase_orders'),
(N'VE100952',N'Shiner LLC',N'purchase_orders');
IF (SELECT COUNT(*) FROM dbo.pst_reports) <> 1
 OR NOT EXISTS (SELECT 1 FROM dbo.pst_reports WHERE pst_id=1 AND pst_description=N'Shiner Combined PST')
 OR (SELECT COUNT(*) FROM dbo.exclusions WHERE rule_scope=N'pst') <> 76
 OR EXISTS (SELECT id,entity,target_table FROM @seed EXCEPT SELECT id,entity,target_table FROM dbo.exclusions WHERE rule_scope=N'pst' AND pst_id=1)
 THROW 50210, 'PST data changed after migration; review rollback scope.', 1;
DELETE FROM dbo.exclusions WHERE rule_scope=N'pst' AND pst_id=1;
DELETE FROM dbo.pst_reports WHERE pst_id=1;
GO
ALTER TABLE dbo.[sales_orders] DROP COLUMN [exclusion];
ALTER TABLE dbo.[sales_orders] DROP COLUMN [intercompany];
ALTER TABLE dbo.[purchase_orders] DROP COLUMN [exclusion];
ALTER TABLE dbo.[purchase_orders] DROP COLUMN [intercompany];
GO
CREATE OR ALTER FUNCTION [dbo].[fnc_is_vendor_exclusion] (
	 @entity NVARCHAR(20)
	,@vendor_id NVARCHAR(20)
	)
RETURNS BIT
AS
/*===============================================================================================================================================
Returns 1 when the entity/vendor combination is configured as a vendor
exclusion in dbo.exclusions; otherwise returns 0.
===============================================================================================================================================*/
BEGIN
	DECLARE @is_exclusion BIT = 0;

	IF EXISTS (
			SELECT 1
			FROM [dbo].[exclusions]
			WHERE [entity] = @entity
				AND [type] = 'exclusion'
				AND [table_name] = 'vendors'
				AND [id] = @vendor_id
				AND [brand_id] = N''
			)
	BEGIN
		SET @is_exclusion = 1;
	END;

	RETURN @is_exclusion;
END;
GO
CREATE OR ALTER FUNCTION [dbo].[fnc_is_vendor_intercompany] (
	 @entity NVARCHAR(20)
	,@vendor_id NVARCHAR(20)
	)
RETURNS BIT
AS
/*===============================================================================================================================================
Returns 1 when the entity/vendor combination is configured as an intercompany
vendor in dbo.exclusions; otherwise returns 0.
===============================================================================================================================================*/
BEGIN
	DECLARE @is_intercompany BIT = 0;

	IF EXISTS (
			SELECT 1
			FROM [dbo].[exclusions]
			WHERE [entity] = @entity
				AND [type] = 'intercompany'
				AND [table_name] = 'vendors'
				AND [id] = @vendor_id
				AND [brand_id] = N''
			)
	BEGIN
		SET @is_intercompany = 1;
	END;

	RETURN @is_intercompany;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[save_margin_rule_snapshot]
	 @taken_by NVARCHAR(200)
	,@reason NVARCHAR(30) = N'manual'
	,@description NVARCHAR(400) = N''
	,@return_row BIT = 1
	,@snapshot_id INT = NULL OUTPUT
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Saves a copy of dbo.exclusions and dbo.deductions as they are now, so they can be put back with
restore_margin_rule_snapshot. The other margin-rule procedures call it before every change (@return_row = 0); the Shiner
Reports portal calls it when a person saves a copy by hand.

@reason: manual, add, delete, restore or recalculation (what is about to happen). @description: free text shown in the
portal. Returns one row (outcome, message, snapshot_id) unless @return_row = 0.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @taken_by = LTRIM(RTRIM(ISNULL(@taken_by, N'')));

	SET @description = LEFT(LTRIM(RTRIM(ISNULL(@description, N''))), 400);

	IF @taken_by = N''
		THROW 50101, 'The @taken_by parameter cannot be blank.', 1;

	IF ISNULL(@reason, N'') NOT IN (N'manual', N'add', N'delete', N'restore', N'recalculation')
		THROW 50102, 'The @reason parameter must be manual, add, delete, restore or recalculation.', 1;

	DECLARE @transaction_started BIT = 0;
	DECLARE @exclusion_rows INT;
	DECLARE @deduction_rows INT;

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;

		END;

		INSERT INTO [dbo].[margin_rule_snapshots] (
			 [taken_by]
			,[reason]
			,[description]
			)
		VALUES (
			 @taken_by
			,@reason
			,@description
			);

		SET @snapshot_id = CAST(SCOPE_IDENTITY() AS INT);

		-- HOLDLOCK: both copies are of one moment, even if someone changes a rule meanwhile.

		INSERT INTO [dbo].[margin_rule_snapshot_exclusions] (
			 [snapshot_id]
			,[entity]
			,[type]
			,[table_name]
			,[id]
			,[brand_id]
			)
		SELECT @snapshot_id
			,ex.[entity]
			,ex.[type]
			,ex.[table_name]
			,ex.[id]
			,ex.[brand_id]

		FROM [dbo].[exclusions] AS ex WITH (HOLDLOCK);

		SET @exclusion_rows = @@ROWCOUNT;

		INSERT INTO [dbo].[margin_rule_snapshot_deductions] (
			 [snapshot_id]
			,[deduction_id]
			,[deduction_type]
			,[deduction_sub_type]
			,[deduction_entity]
			,[deduction_value]
			)
		SELECT @snapshot_id
			,de.[deduction_id]
			,de.[deduction_type]
			,de.[deduction_sub_type]
			,de.[deduction_entity]
			,de.[deduction_value]

		FROM [dbo].[deductions] AS de WITH (HOLDLOCK);

		SET @deduction_rows = @@ROWCOUNT;

		UPDATE [dbo].[margin_rule_snapshots]

		SET [exclusion_rows] = @exclusion_rows
			,[deduction_rows] = @deduction_rows

		WHERE [snapshot_id] = @snapshot_id;

		IF @transaction_started = 1
			COMMIT TRANSACTION;

	END TRY

	BEGIN CATCH
		IF @transaction_started = 1
			AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		THROW;

	END CATCH;

	IF @return_row = 1
		SELECT N'ok' AS [outcome]
			,CONCAT(N'Copy ', @snapshot_id, N' saved: ', @exclusion_rows, N' exclusion and intercompany rules, ', @deduction_rows, N' deductions.') AS [message]
			,@snapshot_id AS [snapshot_id];

END;

GO

CREATE OR ALTER PROCEDURE [dbo].[restore_margin_rule_snapshot]
	 @snapshot_id INT
	,@restored_by NVARCHAR(200)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Puts dbo.exclusions and dbo.deductions back to a saved copy (save_margin_rule_snapshot). Both tables are replaced in one
transaction, after a copy of what they hold now has been saved, so a restore can itself be undone.

dbo.sales is not touched: run run_margin_rule_recalculation afterwards to bring the stored flags and margins into line.
Returns one row: outcome (ok or refused), message, snapshot_id (the copy saved before the restore).
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @restored_by = LTRIM(RTRIM(ISNULL(@restored_by, N'')));

	IF @restored_by = N''
		THROW 50101, 'The @restored_by parameter cannot be blank.', 1;

	DECLARE @refusal NVARCHAR(400);
	DECLARE @taken_at DATETIME2(0);
	DECLARE @description NVARCHAR(400);
	DECLARE @saved_id INT;
	DECLARE @exclusion_rows INT;
	DECLARE @deduction_rows INT;
	DECLARE @log_message NVARCHAR(MAX);
	DECLARE @transaction_started BIT = 0;

	SELECT @taken_at = sn.[taken_at]

	FROM [dbo].[margin_rule_snapshots] AS sn

	WHERE sn.[snapshot_id] = @snapshot_id;

	IF @taken_at IS NULL
		SET @refusal = N'That saved copy no longer exists.';
	ELSE IF APPLOCK_TEST(N'public', N'margin_rule_recalculation', N'Exclusive', N'Session') = 0
		SET @refusal = N'A recalculation is running. Try again when it has finished.';
	ELSE IF EXISTS (
			SELECT se.[entity]

			FROM [dbo].[margin_rule_snapshot_exclusions] AS se

			WHERE se.[snapshot_id] = @snapshot_id

			UNION ALL

			SELECT sd.[deduction_entity]

			FROM [dbo].[margin_rule_snapshot_deductions] AS sd

			WHERE sd.[snapshot_id] = @snapshot_id

			EXCEPT

			SELECT en.[entity]

			FROM [dbo].[entities] AS en
			)
		SET @refusal = N'That saved copy names a company that is no longer in the entities table, so it cannot be restored.';

	IF @refusal IS NOT NULL
	BEGIN
		SELECT N'refused' AS [outcome]
			,@refusal AS [message]
			,CAST(NULL AS INT) AS [snapshot_id];

		RETURN;

	END;

	SET @description = CONCAT(N'Before restoring copy ', @snapshot_id, N' (saved ', CONVERT(NVARCHAR(16), @taken_at, 120), N')');

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;

		END;

		EXEC [dbo].[save_margin_rule_snapshot]
			 @taken_by = @restored_by
			,@reason = N'restore'
			,@description = @description
			,@return_row = 0
			,@snapshot_id = @saved_id OUTPUT;

		DELETE FROM [dbo].[exclusions];

		DELETE FROM [dbo].[deductions];

		INSERT INTO [dbo].[exclusions] (
			 [entity]
			,[type]
			,[table_name]
			,[id]
			,[brand_id]
			)
		SELECT se.[entity]
			,se.[type]
			,se.[table_name]
			,se.[id]
			,se.[brand_id]

		FROM [dbo].[margin_rule_snapshot_exclusions] AS se

		WHERE se.[snapshot_id] = @snapshot_id;

		SET @exclusion_rows = @@ROWCOUNT;

		INSERT INTO [dbo].[deductions] (
			 [deduction_id]
			,[deduction_type]
			,[deduction_sub_type]
			,[deduction_entity]
			,[deduction_value]
			)
		SELECT sd.[deduction_id]
			,sd.[deduction_type]
			,sd.[deduction_sub_type]
			,sd.[deduction_entity]
			,sd.[deduction_value]

		FROM [dbo].[margin_rule_snapshot_deductions] AS sd

		WHERE sd.[snapshot_id] = @snapshot_id;

		SET @deduction_rows = @@ROWCOUNT;

		SET @log_message = CONCAT(N'Restored by ', @restored_by, N' from copy ', @snapshot_id, N' (saved ', CONVERT(NVARCHAR(16), @taken_at, 120), N'): ',
				@exclusion_rows, N' exclusion and intercompany rules, ', @deduction_rows, N' deductions. The rules before the restore are copy ', @saved_id, N'.');

		EXEC [dbo].[write_db_log]
			 @level = N'INFO'
			,@table = N'exclusions'
			,@rows = @exclusion_rows
			,@action = N'restore exclusions and deductions from a saved copy'
			,@message = @log_message;

		IF @transaction_started = 1
			COMMIT TRANSACTION;

	END TRY

	BEGIN CATCH
		IF @transaction_started = 1
			AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		THROW;

	END CATCH;

	SELECT N'ok' AS [outcome]
		,CONCAT(N'Copy ', @snapshot_id, N' restored: ', @exclusion_rows, N' exclusion and intercompany rules, ', @deduction_rows, N' deductions.') AS [message]
		,@saved_id AS [snapshot_id];

END;

GO

CREATE OR ALTER PROCEDURE [dbo].[add_exclusion_rule]
	 @entity NVARCHAR(20)
	,@type NVARCHAR(20)
	,@table_name NVARCHAR(20)
	,@id NVARCHAR(20)
	,@brand_id NVARCHAR(20) = N''
	,@changed_by NVARCHAR(200)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Adds one row to dbo.exclusions for the Shiner Reports portal, after saving a copy of the rules as they are.

@type: exclusion or intercompany. @table_name: customers or vendors. @id: a customer_id or vendor_id that exists.
@brand_id: blank for the whole customer or vendor; a brand is allowed only on a customer exclusion (CK_exclusions_brand_scope).

sales_orders and purchase_orders work their flags out when read, so they follow at once. dbo.sales stores its flags:
run run_margin_rule_recalculation to update them. Returns one row: outcome (ok or refused) and message.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @changed_by = LTRIM(RTRIM(ISNULL(@changed_by, N'')));

	IF @changed_by = N''
		THROW 50101, 'The @changed_by parameter cannot be blank.', 1;

	SET @entity = LTRIM(RTRIM(ISNULL(@entity, N'')));
	SET @type = LOWER(LTRIM(RTRIM(ISNULL(@type, N''))));
	SET @table_name = LOWER(LTRIM(RTRIM(ISNULL(@table_name, N''))));
	SET @id = LTRIM(RTRIM(ISNULL(@id, N'')));
	SET @brand_id = LTRIM(RTRIM(ISNULL(@brand_id, N'')));

	DECLARE @refusal NVARCHAR(400);
	DECLARE @known_entity NVARCHAR(20);
	DECLARE @known_id NVARCHAR(20);
	DECLARE @known_brand NVARCHAR(20) = N'';
	DECLARE @name NVARCHAR(100);
	DECLARE @description NVARCHAR(400);
	DECLARE @log_message NVARCHAR(MAX);
	DECLARE @transaction_started BIT = 0;

	-- The stored values take the spelling of the tables they refer to, whatever was typed.

	SELECT @known_entity = en.[entity]

	FROM [dbo].[entities] AS en

	WHERE en.[entity] = @entity;

	IF @table_name = N'customers'
		SELECT @known_id = cu.[customer_id]
			,@name = cu.[customer_name]

		FROM [dbo].[customers] AS cu

		WHERE cu.[customer_id] = @id;

	IF @table_name = N'vendors'
		SELECT @known_id = ve.[vendor_id]
			,@name = ve.[vendor_name]

		FROM [dbo].[vendors] AS ve

		WHERE ve.[vendor_id] = @id;

	IF @brand_id <> N''
		SELECT @known_brand = br.[brand_id]

		FROM [dbo].[brands] AS br

		WHERE br.[brand_id] = @brand_id;

	IF @known_entity IS NULL
		SET @refusal = N'Choose a company from the list.';
	ELSE IF @type NOT IN (N'exclusion', N'intercompany')
		SET @refusal = N'Choose Exclusion or Intercompany.';
	ELSE IF @table_name NOT IN (N'customers', N'vendors')
		SET @refusal = N'Choose Customer or Vendor.';
	ELSE IF @id = N''
		OR @known_id IS NULL
		SET @refusal = CONCAT(N'There is no ', CASE @table_name WHEN N'customers' THEN N'customer' ELSE N'vendor' END, N' with that number.');
	ELSE IF @brand_id <> N''
		AND NOT (
			@type = N'exclusion'
			AND @table_name = N'customers'
			)
		SET @refusal = N'A brand can only be chosen for a customer exclusion.';
	ELSE IF @brand_id <> N''
		AND @known_brand = N''
		SET @refusal = N'Choose a brand from the list.';
	ELSE IF APPLOCK_TEST(N'public', N'margin_rule_recalculation', N'Exclusive', N'Session') = 0
		SET @refusal = N'A recalculation is running. Try again when it has finished.';
	ELSE IF EXISTS (
			SELECT 1

			FROM [dbo].[exclusions] AS ex

			WHERE ex.[entity] = @known_entity
				AND ex.[type] = @type
				AND ex.[table_name] = @table_name
				AND ex.[id] = @known_id
				AND ex.[brand_id] = @known_brand
			)
		SET @refusal = N'That rule is already in the table.';

	IF @refusal IS NOT NULL
	BEGIN
		SELECT N'refused' AS [outcome]
			,@refusal AS [message];

		RETURN;

	END;

	SET @description = CONCAT(N'Before adding ', @type, N': ', @known_entity, N', ', CASE @table_name WHEN N'customers' THEN N'customer ' ELSE N'vendor ' END, @known_id,
			N' ', ISNULL(@name, N''), CASE WHEN @known_brand <> N'' THEN CONCAT(N', brand ', @known_brand) ELSE N'' END);

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;

		END;

		EXEC [dbo].[save_margin_rule_snapshot]
			 @taken_by = @changed_by
			,@reason = N'add'
			,@description = @description
			,@return_row = 0;

		INSERT INTO [dbo].[exclusions] (
			 [entity]
			,[type]
			,[table_name]
			,[id]
			,[brand_id]
			)
		VALUES (
			 @known_entity
			,@type
			,@table_name
			,@known_id
			,@known_brand
			);

		SET @log_message = CONCAT(N'Added by ', @changed_by, N' in Shiner Reports: ', STUFF(@description, 1, 14, N''), N'.');

		EXEC [dbo].[write_db_log]
			 @level = N'INFO'
			,@table = N'exclusions'
			,@rows = 1
			,@action = N'add exclusion or intercompany rule'
			,@message = @log_message;

		IF @transaction_started = 1
			COMMIT TRANSACTION;

	END TRY

	BEGIN CATCH
		IF @transaction_started = 1
			AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		THROW;

	END CATCH;

	SELECT N'ok' AS [outcome]
		,N'Rule added.' AS [message];

END;

GO

CREATE OR ALTER PROCEDURE [dbo].[delete_exclusion_rule]
	 @entity NVARCHAR(20)
	,@type NVARCHAR(20)
	,@table_name NVARCHAR(20)
	,@id NVARCHAR(20)
	,@brand_id NVARCHAR(20) = N''
	,@changed_by NVARCHAR(200)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Deletes one row of dbo.exclusions (its whole key is given) for the Shiner Reports portal, after saving a copy of the
rules as they are. dbo.sales stores its flags: run run_margin_rule_recalculation to update them.
Returns one row: outcome (ok or refused) and message.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @changed_by = LTRIM(RTRIM(ISNULL(@changed_by, N'')));

	IF @changed_by = N''
		THROW 50101, 'The @changed_by parameter cannot be blank.', 1;

	SET @entity = ISNULL(@entity, N'');
	SET @type = ISNULL(@type, N'');
	SET @table_name = ISNULL(@table_name, N'');
	SET @id = ISNULL(@id, N'');
	SET @brand_id = ISNULL(@brand_id, N'');

	DECLARE @refusal NVARCHAR(400);
	DECLARE @description NVARCHAR(400);
	DECLARE @log_message NVARCHAR(MAX);
	DECLARE @transaction_started BIT = 0;

	IF NOT EXISTS (
			SELECT 1

			FROM [dbo].[exclusions] AS ex

			WHERE ex.[entity] = @entity
				AND ex.[type] = @type
				AND ex.[table_name] = @table_name
				AND ex.[id] = @id
				AND ex.[brand_id] = @brand_id
			)
		SET @refusal = N'That rule is no longer in the table.';
	ELSE IF APPLOCK_TEST(N'public', N'margin_rule_recalculation', N'Exclusive', N'Session') = 0
		SET @refusal = N'A recalculation is running. Try again when it has finished.';

	IF @refusal IS NOT NULL
	BEGIN
		SELECT N'refused' AS [outcome]
			,@refusal AS [message];

		RETURN;

	END;

	SET @description = CONCAT(N'Before deleting ', @type, N': ', @entity, N', ', @table_name, N' ', @id, CASE WHEN @brand_id <> N'' THEN CONCAT(N', brand ', @brand_id) ELSE N'' END);

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;

		END;

		EXEC [dbo].[save_margin_rule_snapshot]
			 @taken_by = @changed_by
			,@reason = N'delete'
			,@description = @description
			,@return_row = 0;

		DELETE ex

		FROM [dbo].[exclusions] AS ex

		WHERE ex.[entity] = @entity
			AND ex.[type] = @type
			AND ex.[table_name] = @table_name
			AND ex.[id] = @id
			AND ex.[brand_id] = @brand_id;

		SET @log_message = CONCAT(N'Deleted by ', @changed_by, N' in Shiner Reports: ', STUFF(@description, 1, 16, N''), N'.');

		EXEC [dbo].[write_db_log]
			 @level = N'INFO'
			,@table = N'exclusions'
			,@rows = 1
			,@action = N'delete exclusion or intercompany rule'
			,@message = @log_message;

		IF @transaction_started = 1
			COMMIT TRANSACTION;

	END TRY

	BEGIN CATCH
		IF @transaction_started = 1
			AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		THROW;

	END CATCH;

	SELECT N'ok' AS [outcome]
		,N'Rule deleted.' AS [message];

END;

GO
CREATE OR ALTER FUNCTION [dbo].[fnc_is_customer_exclusion] (
	 @entity NVARCHAR(20)
	,@customer_id NVARCHAR(20)
	,@brand_id NVARCHAR(20)
	)
RETURNS BIT
AS
/*===============================================================================================================================================
Returns 1 when the entity/customer combination is configured as a customer
exclusion in dbo.exclusions for all brands (blank brand_id) or the supplied brand; otherwise returns 0.
===============================================================================================================================================*/
BEGIN
	DECLARE @is_exclusion BIT = 0;

	IF EXISTS (
			SELECT 1
			FROM [dbo].[exclusions]
			WHERE [entity] = @entity
				AND [type] = 'exclusion'
				AND [table_name] = 'customers'
				AND [id] = @customer_id
				AND ([brand_id] = N'' OR [brand_id] = @brand_id)
			)
	BEGIN
		SET @is_exclusion = 1;
	END;

	RETURN @is_exclusion;
END;
GO
CREATE OR ALTER FUNCTION [dbo].[fnc_is_customer_intercompany] (
	 @entity NVARCHAR(20)
	,@customer_id NVARCHAR(20)
	)
RETURNS BIT
AS
/*===============================================================================================================================================
Returns 1 when the entity/customer combination is configured as an intercompany
customer in dbo.exclusions; otherwise returns 0.
===============================================================================================================================================*/
BEGIN
	DECLARE @is_intercompany BIT = 0;

	IF EXISTS (
			SELECT 1
			FROM [dbo].[exclusions]
			WHERE [entity] = @entity
				AND [type] = 'intercompany'
				AND [table_name] = 'customers'
				AND [id] = @customer_id
				AND [brand_id] = N''
			)
	BEGIN
		SET @is_intercompany = 1;
	END;

	RETURN @is_intercompany;
END;
GO
ALTER TABLE dbo.[sales_orders] ADD [exclusion] AS ([dbo].[fnc_is_customer_exclusion]([entity],[sell_to_customer_id],CONVERT([nvarchar](20),left([item_id],(3)))));
ALTER TABLE dbo.[sales_orders] ADD [intercompany] AS ([dbo].[fnc_is_customer_intercompany]([entity],[sell_to_customer_id]));
ALTER TABLE dbo.[purchase_orders] ADD [exclusion] AS ([dbo].[fnc_is_vendor_exclusion]([entity],[vendor_id]));
ALTER TABLE dbo.[purchase_orders] ADD [intercompany] AS ([dbo].[fnc_is_vendor_intercompany]([entity],[vendor_id]));
GO
DROP FUNCTION dbo.fnc_is_pst_exclusion;
ALTER TABLE dbo.exclusions DROP CONSTRAINT FK_exclusions_pst_reports, CK_exclusions_report_scope;
DROP INDEX UX_exclusions_rule ON dbo.exclusions;
ALTER TABLE dbo.exclusions DROP CONSTRAINT PK_exclusions, DF_exclusions_rule_scope, DF_exclusions_target_table;
ALTER TABLE dbo.exclusions DROP COLUMN exclusion_rule_id,rule_scope,pst_id,target_table;
ALTER TABLE dbo.exclusions ADD CONSTRAINT PK_exclusions PRIMARY KEY CLUSTERED (entity,[type],table_name,id,brand_id);
ALTER TABLE dbo.pst_reports DROP CONSTRAINT DF_pst_reports_last_updated;
ALTER TABLE dbo.pst_reports DROP COLUMN last_updated;
ALTER TABLE dbo.pst_reports ALTER COLUMN exclusion_entity NVARCHAR(20) NOT NULL;
ALTER TABLE dbo.pst_reports ALTER COLUMN exclusion_id NVARCHAR(20) NOT NULL;
COMMIT;

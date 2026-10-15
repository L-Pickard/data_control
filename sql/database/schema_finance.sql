USE [data_control];

GO

-- [finance] holds finance's own permanent records, created on 15 October 2026 for the inventory cost datasets
-- (inventory_cost, inventory_cost_lines, the checks and their warning lists, and the procedures that queue, build
-- and delete them). Unlike most of [dbo], nothing here is a reloadable copy of NAV: the table files create only when
-- missing and never drop. Not to be confused with the separate Finance database on this server, which this schema
-- has nothing to do with.
-- Owned by [dbo] so ownership chaining lets the procedures here read and write [dbo] tables (items, entities,
-- brands, db_log) and the portal needs only EXECUTE on the procedures it calls. Needs a db_owner to run.
IF SCHEMA_ID(N'finance') IS NULL
	EXEC (N'CREATE SCHEMA [finance] AUTHORIZATION [dbo];');

GO

USE [data_control];
GO

IF COL_LENGTH(N'dbo.item_packaging', N'brand_type') IS NULL
BEGIN
    ALTER TABLE [dbo].[item_packaging]
        ADD [brand_type] NVARCHAR(100) NULL;
END;
GO

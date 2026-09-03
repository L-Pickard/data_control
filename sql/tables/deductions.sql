USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

DROP TABLE

IF EXISTS [dbo].[deductions]
	CREATE TABLE [dbo].[deductions] (
		 [deduction_id] NVARCHAR(20) NOT NULL
		,[deduction_type] NVARCHAR(50) NOT NULL
        ,[deduction_sub_type] NVARCHAR(30) NOT NULL
        ,[deduction_entity] NVARCHAR(20) NOT NULL
		,[deduction_value] DECIMAL(38, 20) NOT NULL
		,CONSTRAINT [PK_deductions] PRIMARY KEY CLUSTERED (
			 [deduction_id]
			,[deduction_type]
            ,[deduction_sub_type]
			,[deduction_entity]
			)
		,CONSTRAINT [FK_deductions_entities] FOREIGN KEY ([deduction_entity]) REFERENCES [dbo].[entities] ([entity])
		);

INSERT INTO [dbo].[deductions] (
	 [deduction_id]
	,[deduction_type]
    ,[deduction_sub_type]
    ,[deduction_entity]
	,[deduction_value]
	)

VALUES
     ('ABR', 'Brand Royalty', '', 'Example Ltd', 0.08)
    ,('ABA', 'Brand Royalty', '', 'Example Ltd', 0.08)
    ,('BIR', 'Brand Royalty', '', 'Example Ltd', 0.08)
    ,('TSS', 'Brand Royalty', '', 'Example Ltd', 0.08)
    ,('INA', 'Brand Royalty', '', 'Example Ltd', 0.08)
    ,('SCA', 'Brand Royalty', '', 'Example Ltd', 0.08)
    ,('BUL', 'Brand Royalty', 'PCO', 'Example Ltd', 0.06)
    ,('BUL', 'Brand Royalty', '', 'Example Ltd', 0.05)
    ,('ABR', 'Brand Royalty', '', 'Example BV', 0.08)
    ,('ABA', 'Brand Royalty', '', 'Example BV', 0.08)
    ,('BIR', 'Brand Royalty', '', 'Example BV', 0.08)
    ,('TSS', 'Brand Royalty', '', 'Example BV', 0.08)
    ,('INA', 'Brand Royalty', '', 'Example BV', 0.08)
    ,('SCA', 'Brand Royalty', '', 'Example BV', 0.08)
    ,('BUL', 'Brand Royalty', 'PCO', 'Example BV', 0.06)
    ,('BUL', 'Brand Royalty', '', 'Example BV', 0.05)
    ,('ABR', 'Brand Royalty', '', 'Example LLC', 0.065)
    ,('ABA', 'Brand Royalty', '', 'Example LLC', 0.065)
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example Ltd', 0.13)    -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', 'HLY', 'Example Ltd', 0.15) -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example Ltd', 0.05)    -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example Ltd', 0.025)   -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example Ltd', 0.025)   -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example BV', 0.05)    -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example BV', 0.045)   -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example BV', 0.04)    -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example BV', 0.04)    -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example BV', 0.03)    -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example BV', 0.03)    -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example BV', 0.025)   -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example BV', 0.02)    -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example BV', 0.02)    -- Example Customer
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example BV', 0.02)    -- Sport 2002
    ,('CUSTOMER_001', 'Customer Rebate', '', 'Example BV', 0.02)    -- Example Customer

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
     ('ABR', 'Brand Royalty', '', 'Shiner Ltd', 0.08)
    ,('ABA', 'Brand Royalty', '', 'Shiner Ltd', 0.08)
    ,('BIR', 'Brand Royalty', '', 'Shiner Ltd', 0.08)
    ,('TSS', 'Brand Royalty', '', 'Shiner Ltd', 0.08)
    ,('INA', 'Brand Royalty', '', 'Shiner Ltd', 0.08)
    ,('SCA', 'Brand Royalty', '', 'Shiner Ltd', 0.08)
    ,('BUL', 'Brand Royalty', 'PCO', 'Shiner Ltd', 0.06)
    ,('BUL', 'Brand Royalty', '', 'Shiner Ltd', 0.05)
    ,('ABR', 'Brand Royalty', '', 'Shiner B.V', 0.08)
    ,('ABA', 'Brand Royalty', '', 'Shiner B.V', 0.08)
    ,('BIR', 'Brand Royalty', '', 'Shiner B.V', 0.08)
    ,('TSS', 'Brand Royalty', '', 'Shiner B.V', 0.08)
    ,('INA', 'Brand Royalty', '', 'Shiner B.V', 0.08)
    ,('SCA', 'Brand Royalty', '', 'Shiner B.V', 0.08)
    ,('BUL', 'Brand Royalty', 'PCO', 'Shiner B.V', 0.06)
    ,('BUL', 'Brand Royalty', '', 'Shiner B.V', 0.05)
    ,('ABR', 'Brand Royalty', '', 'Shiner LLC', 0.065)
    ,('ABA', 'Brand Royalty', '', 'Shiner LLC', 0.065)
    ,('CU105862', 'Customer Rebate', '', 'Shiner Ltd', 0.13)    -- Amazon
    ,('CU105862', 'Customer Rebate', 'HLY', 'Shiner Ltd', 0.15) -- Amazon
    ,('CU100037', 'Customer Rebate', '', 'Shiner Ltd', 0.05)    -- ASOS
    ,('CU105598', 'Customer Rebate', '', 'Shiner Ltd', 0.025)   -- Smyths
    ,('CU105389', 'Customer Rebate', '', 'Shiner Ltd', 0.025)   -- Sports Direct
    ,('CU109640', 'Customer Rebate', '', 'Shiner B.V', 0.05)    -- ASOS
    ,('CU103027', 'Customer Rebate', '', 'Shiner B.V', 0.045)   -- Intersport France SA
    ,('CU109334', 'Customer Rebate', '', 'Shiner B.V', 0.04)    -- About You SE & Co. KG
    ,('CU101067', 'Customer Rebate', '', 'Shiner B.V', 0.04)    -- Sport 2000
    ,('CU100487', 'Customer Rebate', '', 'Shiner B.V', 0.03)    -- Blue Tomato GmbH
    ,('CU103346', 'Customer Rebate', '', 'Shiner B.V', 0.03)    -- Spartoo
    ,('CU105597', 'Customer Rebate', '', 'Shiner B.V', 0.025)   -- Smyths
    ,('CU110281', 'Customer Rebate', '', 'Shiner B.V', 0.02)    -- Maple Leaf
    ,('CU101352', 'Customer Rebate', '', 'Shiner B.V', 0.02)    -- Skatedeluxe
    ,('CU103309', 'Customer Rebate', '', 'Shiner B.V', 0.02)    -- Sport 2002
    ,('CU104900', 'Customer Rebate', '', 'Shiner B.V', 0.02)    -- Zmart Skating

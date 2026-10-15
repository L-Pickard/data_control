-- Inventory cost check (Shiner Ltd, Shiner B.V): per company, the counts of entries for finance.inventory_cost_checks
-- (the loader adds the receipt lines from inventory_cost_receipts.sql). Validated read-only on shinersql02
-- (15 Oct 2026). Parameter: ? = the as-of date.
--   unadjusted_entries  item ledger entries still flagged "Applied Entry to Adjust" (FIFO: cost adjustment has not
--                       reached them yet), as the flag is now. A WARNING, not a blocker, scoped to what can affect
--                       the dataset (user decisions, 15 Oct 2026): the company's dataset location and entries posted
--                       in the 12 months up to the as-of date (NAV keeps a few flagged every month, back to 2013).
--                       inventory_cost_unadjusted.sql lists the same entries.
--   unposted_entries    value entries posted on or before the date, whole company, whose actual cost differs from the
--                       cost posted to the G/L (Post Inventory Cost to G/L runs per company). The only blocker.
DECLARE @as_of AS DATETIME = CAST(? AS DATETIME);
DECLARE @day_after AS DATETIME = DATEADD(DAY, 1, @as_of);
DECLARE @cut_off AS DATETIME = DATEADD(MONTH, - 12, @day_after);

SELECT N'Shiner Ltd' AS [entity]
	,(
		SELECT COUNT(*)

		FROM [Shiner$Item Ledger Entry] AS il

		WHERE il.[Applied Entry to Adjust] = 1
			AND il.[Location Code] = N'BRISTOL'
			AND il.[Posting Date] >= @cut_off
			AND il.[Posting Date] < @day_after
		) AS [unadjusted_entries]
	,(
		SELECT COUNT(*)

		FROM [Shiner$Value Entry] AS ve

		WHERE ve.[Cost Amount (Actual)] <> ve.[Cost Posted to G_L]
			AND ve.[Posting Date] < @day_after
		) AS [unposted_entries]


UNION ALL

SELECT N'Shiner B.V' AS [entity]
	,(
		SELECT COUNT(*)

		FROM [Shiner BV$Item Ledger Entry] AS il

		WHERE il.[Applied Entry to Adjust] = 1
			AND il.[Location Code] = N'3PL'
			AND il.[Posting Date] >= @cut_off
			AND il.[Posting Date] < @day_after
		) AS [unadjusted_entries]
	,(
		SELECT COUNT(*)

		FROM [Shiner BV$Value Entry] AS ve

		WHERE ve.[Cost Amount (Actual)] <> ve.[Cost Posted to G_L]
			AND ve.[Posting Date] < @day_after
		) AS [unposted_entries];

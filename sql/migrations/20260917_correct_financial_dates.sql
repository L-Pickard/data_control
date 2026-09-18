USE [data_control];
GO
SET XACT_ABORT ON;
SET LANGUAGE us_english;
BEGIN TRANSACTION;

-- From FY 2026/27, May includes 30 April. Earlier years start on 1 May.
-- The transition FY 2025/26 ends on 29 April 2026.
UPDATE d
SET financial_year_no = YEAR(p.year_start) + 1,
    financial_year_short = n.year_label,
    financial_year_name = 'FY ' + n.year_label,
    financial_year_start = p.year_start,
    financial_year_end = e.year_end,
    financial_year_day_count = DATEDIFF(DAY, p.year_start, e.year_end) + 1,
    day_of_financial_year = DATEDIFF(DAY, p.year_start, d.calendar_date) + 1,
    days_remaining_in_financial_year = DATEDIFF(DAY, d.calendar_date, e.year_end),
    financial_week_no = DATEDIFF(DAY, p.year_start, d.calendar_date) / 7 + 1,
    financial_quarter = m.quarter_no,
    financial_quarter_name = CONCAT('Q', m.quarter_no),
    financial_quarter_start = p.quarter_start,
    financial_quarter_end = e.quarter_end,
    day_of_financial_quarter = DATEDIFF(DAY, p.quarter_start, d.calendar_date) + 1,
    financial_quarter_year = CONCAT('Q', m.quarter_no, ' ', n.year_label),
    financial_month_no = m.month_no,
    financial_month_start = p.month_start,
    financial_month_end = e.month_end,
    day_of_financial_month = DATEDIFF(DAY, p.month_start, d.calendar_date) + 1,
    month_name = DATENAME(MONTH, a.label_date),
    month_name_abbreviation = LEFT(DATENAME(MONTH, a.label_date), 3),
    month_abbreviation_year = LEFT(DATENAME(MONTH, a.label_date), 3) + '-' + RIGHT(CONVERT(char(4), YEAR(a.label_date)), 2),
    month_financial_year = LEFT(DATENAME(MONTH, a.label_date), 3) + ' ' + n.year_label,
    financial_month_year_no = ((YEAR(p.year_start) + 1) % 100) * 100 + m.month_no
FROM dbo.dates d
CROSS APPLY (SELECT CASE WHEN d.calendar_date >= '20260430' AND MONTH(d.calendar_date) = 4 AND DAY(d.calendar_date) = 30
    THEN DATEADD(DAY, 1, d.calendar_date) ELSE d.calendar_date END AS label_date) a
CROSS APPLY (SELECT (MONTH(a.label_date) + 7) % 12 + 1 AS month_no,
    ((MONTH(a.label_date) + 7) % 12) / 3 + 1 AS quarter_no,
    YEAR(a.label_date) - CASE WHEN MONTH(a.label_date) < 5 THEN 1 ELSE 0 END AS start_year) m
CROSS APPLY (SELECT CASE WHEN m.start_year >= 2026 THEN DATEFROMPARTS(m.start_year, 4, 30) ELSE DATEFROMPARTS(m.start_year, 5, 1) END AS year_start,
    CASE WHEN m.quarter_no = 1 AND m.start_year >= 2026 THEN DATEFROMPARTS(m.start_year, 4, 30)
         ELSE DATEADD(MONTH, (m.quarter_no - 1) * 3, DATEFROMPARTS(m.start_year, 5, 1)) END AS quarter_start,
    CASE WHEN MONTH(a.label_date) = 5 AND m.start_year >= 2026 THEN DATEFROMPARTS(YEAR(a.label_date), 4, 30)
         ELSE DATEFROMPARTS(YEAR(a.label_date), MONTH(a.label_date), 1) END AS month_start) p
CROSS APPLY (SELECT DATEFROMPARTS(m.start_year + 1, 4, CASE WHEN m.start_year >= 2025 THEN 29 ELSE 30 END) AS year_end,
    CASE WHEN m.quarter_no = 4 THEN DATEFROMPARTS(m.start_year + 1, 4, CASE WHEN m.start_year >= 2025 THEN 29 ELSE 30 END)
         ELSE EOMONTH(DATEADD(MONTH, m.quarter_no * 3 - 1, DATEFROMPARTS(m.start_year, 5, 1))) END AS quarter_end,
    CASE WHEN MONTH(a.label_date) = 4 AND YEAR(a.label_date) >= 2026 THEN DATEFROMPARTS(YEAR(a.label_date), 4, 29)
         ELSE EOMONTH(a.label_date) END AS month_end) e
CROSS APPLY (SELECT RIGHT(CONVERT(char(4), m.start_year), 2) + '-' + RIGHT(CONVERT(char(4), m.start_year + 1), 2) AS year_label) n
WHERE d.is_placeholder = 0
  AND d.calendar_date >= '20260430';

SELECT @@ROWCOUNT AS corrected_dates;
COMMIT TRANSACTION;
GO

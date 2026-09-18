"""Validate every source attribute and generate a full SQL table/view audit.

Run with --sql-output PATH, then run that file with tools/db-query.ps1.
The generated SQL previews the migration in a transaction and rolls it back.
"""
import argparse
import calendar
import csv
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def month_end(day):
    return day.replace(day=calendar.monthrange(day.year, day.month)[1])


def periods(day):
    label = day + timedelta(days=1) if day.year >= 2026 and (day.month, day.day) == (4, 30) else day
    year = label.year - (label.month < 5)
    number = (label.month - 5) % 12 + 1
    quarter = (number - 1) // 3 + 1
    ys = date(year, 4, 30) if year >= 2026 else date(year, 5, 1)
    ye = date(year + 1, 4, 29 if year >= 2025 else 30)
    return (label, year, number, quarter, ys, ye,
            date(label.year, 4, 30) if label.month == 5 and year >= 2026 else label.replace(day=1),
            date(label.year, 4, 29) if label.month == 4 and label.year >= 2026 else month_end(label),
            [ys, date(year, 8, 1), date(year, 11, 1), date(year + 1, 2, 1)][quarter - 1],
            [date(year, 7, 31), date(year, 10, 31), date(year + 1, 1, 31), ye][quarter - 1])


def expected(day):
    label, year, number, quarter, ys, ye, ms, me, qs, qe = periods(day)
    short = f'{year % 100:02}-{(year + 1) % 100:02}'
    cq = (day.month - 1) // 3 + 1
    cs = date(day.year, cq * 3 - 2, 1)
    iso = day.isocalendar()
    week = lambda d: (d.timetuple().tm_yday - 1 + date(d.year, 1, 1).weekday()) // 7 + 1
    return dict(zip(
        ['date','day','day_of_week','day_of_year','day_name','day_name_abbreviation',
         'week_of_year','week_of_month','year','month_no','month_&_year','year_&_month_no',
         'month_start','month_end','quarter','quarter_full','calendar_quarter_start','calendar_quarter_end',
         'iso_year','iso_week_no','year_week','financial_year_short','financial_year_long','financial_year_full',
         'financial_year_start','financial_year_end','financial_year_day_count','day_of_financial Year',
         'days_remaining_in_financial_Year','financial_week_no','financial_quarter','financial_quarter_full',
         'financial_quarter_start','financial_quarter_end','day_of_financial_quarter','financial_quarter_&_year',
         'financial_month_no','financial_month_start','financial_month_end','day_of_financial_month',
         'month_name','month_name_abbreviation','month_abbreviation_&_year','month_name_&_financial_year','financial_month_&_year'],
        [day, day.day, day.weekday(), day.timetuple().tm_yday, calendar.day_name[day.weekday()], calendar.day_abbr[day.weekday()],
         week(day), week(day) - week(day.replace(day=1)) + 1, day.year, day.month, day.strftime('%b %Y'), day.year * 100 + day.month,
         day.replace(day=1), month_end(day), cq, f'Q{cq}', cs, month_end(date(day.year, cq * 3, 1)),
         iso.year, iso.week, f'{iso.year}-W{iso.week:02}', year + 1, short, f'FY {short}',
         ys, ye, (ye-ys).days+1, (day-ys).days+1, (ye-day).days, (day-ys).days//7+1,
         quarter, f'Q{quarter}', qs, qe, (day-qs).days+1, f'Q{quarter} {short}',
         number, ms, me, (day-ms).days+1, calendar.month_name[label.month], calendar.month_abbr[label.month],
         label.strftime('%b-%y'), f'{calendar.month_abbr[label.month]} {short}', ((year+1)%100)*100+number], strict=True))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sql-output', type=Path, required=True)
    args = parser.parse_args()
    import sys
    sys.path.insert(0, str(ROOT))
    from shinerutils.updates.dates import COLUMN_RENAMES, prepare_dates_dataframe
    prepare_dates_dataframe()
    with (ROOT / 'documents/dates_import.csv').open(newline='') as handle:
        rows = list(csv.DictReader(handle))
    errors = []
    for row in rows:
        for key, value in expected(date.fromisoformat(row['date'])).items():
            if row[key] != str(value):
                errors.append((row['date'], key, row[key], str(value)))
    if errors:
        from collections import Counter
        print('Source errors by column:', Counter(e[1] for e in errors))
        print('Examples:', errors[:20])
        raise SystemExit(1)
    print(f'All {len(rows)} source rows and {len(rows[0])} attributes validated.')
    columns = [COLUMN_RENAMES.get(c, c) for c in rows[0]]
    names = ','.join(f'[{c}]' for c in columns)
    sql = ["USE data_control; SET XACT_ABORT ON;\n",
           (ROOT / 'sql/migrations/20260917_correct_financial_dates.sql').read_text().replace('COMMIT TRANSACTION;', '')]
    sql.append(f'SELECT TOP (0) {names} INTO #expected FROM dbo.dates;\n')
    quote = lambda v: "'" + v.replace("'", "''") + "'"
    for offset in range(0, len(rows), 500):
        values = ',\n'.join('(' + ','.join(quote(v) for v in row.values()) + ')' for row in rows[offset:offset+500])
        sql.append(f'INSERT INTO #expected ({names}) VALUES {values};\n')
    sql.append(f"""
IF EXISTS (SELECT {names} FROM dbo.dates WHERE is_placeholder=0 EXCEPT SELECT {names} FROM #expected)
 OR EXISTS (SELECT {names} FROM #expected EXCEPT SELECT {names} FROM dbo.dates WHERE is_placeholder=0)
 THROW 51000, 'Actual dates table differs from independently validated source', 1;
IF EXISTS (SELECT calendar_date FROM dbo.dates GROUP BY calendar_date HAVING COUNT(*)<>1)
 THROW 51000, 'Duplicate dates', 1;
IF EXISTS (SELECT 1 FROM dbo.dates WHERE date_key <> YEAR(calendar_date)*10000+MONTH(calendar_date)*100+DAY(calendar_date))
 THROW 51000, 'Incorrect date key', 1;
IF (SELECT COUNT(*) FROM dbo.dates WHERE is_placeholder=1) <> 2
 OR EXISTS (SELECT 1 FROM dbo.dates WHERE is_placeholder=1 AND calendar_date NOT IN ('19000101','19010101'))
 THROW 51000, 'Unexpected placeholders', 1;
""")
    for column in columns[1:]:
        sql.append(f"IF EXISTS (SELECT 1 FROM dbo.dates WHERE is_placeholder=1 AND [{column}] IS NOT NULL) THROW 51000, 'Placeholder attributes must be null', 1;\n")
    view = (ROOT / 'sql/views/date_catalogue.sql').read_text().split('AS\n', 1)[1].rsplit('GO', 1)[0]
    cases = ['2026-09-17','2026-04-29','2026-04-30','2026-05-01','2026-05-31',
             '2026-06-01','2026-07-31','2026-08-01','2026-10-31','2026-11-01',
             '2027-01-31','2027-02-01','2028-02-29','2027-01-01',
             '2025-04-30','2025-05-01','2024-02-29']
    for case in cases:
        day = date.fromisoformat(case)
        label, year, number, quarter, ys, ye, ms, me, qs, qe = periods(day)
        pm = periods(ms - timedelta(days=1))
        pq = periods(qs - timedelta(days=1))
        py = periods(ys - timedelta(days=1))
        rolling_year, rolling_month = divmod(label.year * 12 + label.month - 1 - 11, 12)
        rs = periods(date(rolling_year, rolling_month + 1, 1))[6]
        monday = day - timedelta(days=day.weekday())
        ranges = {
            'is_today': (day,day), 'is_yesterday': (day-timedelta(days=1),day-timedelta(days=1)),
            'is_current_week': (monday,monday+timedelta(days=6)),
            'is_current_month': (day.replace(day=1),month_end(day)),
            'is_current_financial_month': (ms,me), 'is_current_financial_quarter': (qs,qe),
            'is_current_financial_year': (ys,ye), 'is_previous_financial_year': (py[4],py[5]),
            'is_financial_month_to_date': (ms,day), 'is_financial_quarter_to_date': (qs,day),
            'is_financial_year_to_date': (ys,day), 'is_last_financial_month': (pm[6],pm[7]),
            'is_last_financial_quarter': (pq[8],pq[9]), 'is_last_financial_year': (py[4],py[5]),
            'is_rolling_12_financial_months': (rs,me),
        }
        query = view.replace('SYSDATETIME()', f"CAST('{case}' AS date)").replace('FROM [dbo].[dates] AS dates', 'INTO #actual\nFROM [dbo].[dates] AS dates')
        sql.append(';'+query+'\n')
        sql.append("IF (SELECT COUNT(*) FROM #actual) <> (SELECT COUNT(*) FROM #expected) THROW 51000, 'View row count mismatch', 1;\n")
        for flag, (start,end) in ranges.items():
            sql.append(f"IF EXISTS (SELECT 1 FROM #actual WHERE [{flag}] <> CASE WHEN calendar_date BETWEEN '{start}' AND '{end}' THEN 1 ELSE 0 END) THROW 51000, '{case}: {flag} failed', 1;\n")
        sql.append('DROP TABLE #actual;\nGO\n')
    sql.append("SELECT 'PASS: all table attributes; 15 view flags across 17 boundary dates' AS result;\nROLLBACK TRANSACTION;\n")
    args.sql_output.write_text(''.join(sql), encoding='utf-8')


if __name__ == '__main__':
    main()

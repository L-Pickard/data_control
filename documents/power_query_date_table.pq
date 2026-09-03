let
    // ============================================================
    // SETTINGS
    // ============================================================
    StartDate = #date(2007, 5, 1),
    EndDate = #date(2050, 12, 31),

    // Old financial year: 01 May - 30 April
    // Transition FY25-26: 01 May 2025 - 29 April 2026
    // New financial year from 30/04/2026: 30 April - 29 April
    FinancialYearChangeDate = #date(2026, 4, 30),

    OldFinancialYearStartMonth = 5,
    OldFinancialYearStartDay = 1,

    NewFinancialYearStartMonth = 4,
    NewFinancialYearStartDay = 30,

    Today = Date.From(DateTime.LocalNow()),

    // Add any company-specific / one-off non-working dates here.
    // Standard England & Wales bank holidays are calculated separately below.
    AdditionalNonWorkingDates = {},


    // ============================================================
    // HELPER FUNCTIONS
    // ============================================================

    // Nth occurrence of a weekday in a month.
    // Monday = 0 ... Sunday = 6.
    NthWeekdayOfMonth = (YearNumber as number, MonthNumber as number, WeekdayNumber as number, N as number) as date =>
        let
            FirstDate = #date(YearNumber, MonthNumber, 1),
            Offset = Number.Mod(WeekdayNumber - Date.DayOfWeek(FirstDate, Day.Monday) + 7, 7),
            Result = Date.AddDays(FirstDate, Offset + ((N - 1) * 7))
        in
            Result,

    // Last occurrence of a weekday in a month.
    // Monday = 0 ... Sunday = 6.
    LastWeekdayOfMonth = (YearNumber as number, MonthNumber as number, WeekdayNumber as number) as date =>
        let
            LastDate = Date.EndOfMonth(#date(YearNumber, MonthNumber, 1)),
            Offset = Number.Mod(Date.DayOfWeek(LastDate, Day.Monday) - WeekdayNumber + 7, 7),
            Result = Date.AddDays(LastDate, -Offset)
        in
            Result,

    // Gregorian Easter Sunday.
    EasterSunday = (YearNumber as number) as date =>
        let
            a = Number.Mod(YearNumber, 19),
            b = Number.IntegerDivide(YearNumber, 100),
            c = Number.Mod(YearNumber, 100),
            d = Number.IntegerDivide(b, 4),
            e = Number.Mod(b, 4),
            f = Number.IntegerDivide(b + 8, 25),
            g = Number.IntegerDivide(b - f + 1, 3),
            h = Number.Mod(19 * a + b - d - g + 15, 30),
            i = Number.IntegerDivide(c, 4),
            k = Number.Mod(c, 4),
            l = Number.Mod(32 + 2 * e + 2 * i - h - k, 7),
            m = Number.IntegerDivide(a + 11 * h + 22 * l, 451),
            MonthNumber = Number.IntegerDivide(h + l - 7 * m + 114, 31),
            DayNumber = Number.Mod(h + l - 7 * m + 114, 31) + 1
        in
            #date(YearNumber, MonthNumber, DayNumber),

    // England & Wales Christmas / Boxing Day substitute-day logic.
    ChristmasBankHoliday = (YearNumber as number) as date =>
        let
            Christmas = #date(YearNumber, 12, 25),
            Dow = Date.DayOfWeek(Christmas, Day.Monday)
        in
            if Dow = 5 then #date(YearNumber, 12, 27)
            else if Dow = 6 then #date(YearNumber, 12, 27)
            else Christmas,

    BoxingDayBankHoliday = (YearNumber as number) as date =>
        let
            Christmas = #date(YearNumber, 12, 25),
            BoxingDay = #date(YearNumber, 12, 26),
            ChristmasDow = Date.DayOfWeek(Christmas, Day.Monday),
            BoxingDow = Date.DayOfWeek(BoxingDay, Day.Monday)
        in
            if ChristmasDow = 5 then #date(YearNumber, 12, 28)
            else if ChristmasDow = 6 then #date(YearNumber, 12, 28)
            else if BoxingDow = 5 then #date(YearNumber, 12, 28)
            else if BoxingDow = 6 then #date(YearNumber, 12, 28)
            else BoxingDay,

    NewYearsDayBankHoliday = (YearNumber as number) as date =>
        let
            NewYear = #date(YearNumber, 1, 1),
            Dow = Date.DayOfWeek(NewYear, Day.Monday)
        in
            if Dow = 5 then #date(YearNumber, 1, 3)
            else if Dow = 6 then #date(YearNumber, 1, 2)
            else NewYear,


    // ============================================================
    // DATE LIST
    // ============================================================
    NumberOfDays = Duration.Days(EndDate - StartDate),

    Dates =
        List.Dates(
            StartDate,
            NumberOfDays + 1,
            #duration(1, 0, 0, 0)
        ),

    #"Converted to Table" =
        Table.FromList(
            Dates,
            Splitter.SplitByNothing(),
            {"Date"},
            null,
            ExtraValues.Error
        ),

    #"Changed Date Type" =
        Table.TransformColumnTypes(
            #"Converted to Table",
            {{"Date", type date}}
        ),


    // ============================================================
    // STANDARD CALENDAR COLUMNS
    // ============================================================
    #"Added Year" =
        Table.AddColumn(
            #"Changed Date Type",
            "Year",
            each Date.Year([Date]),
            Int64.Type
        ),

    #"Added Month" =
        Table.AddColumn(
            #"Added Year",
            "Month",
            each Date.Month([Date]),
            Int64.Type
        ),

    #"Added Month Name" =
        Table.AddColumn(
            #"Added Month",
            "Month Name",
            each Date.MonthName([Date]),
            type text
        ),

    #"Added Month Name Abb" =
        Table.AddColumn(
            #"Added Month Name",
            "Month Name Abb",
            each Text.Start([Month Name], 3),
            type text
        ),

    #"Added Year Month" =
        Table.AddColumn(
            #"Added Month Name Abb",
            "Year Month",
            each [Month Name Abb] & " " & Number.ToText([Year]),
            type text
        ),

    #"Added Year Month Number" =
        Table.AddColumn(
            #"Added Year Month",
            "Year Month Number",
            each ([Year] * 100) + [Month],
            Int64.Type
        ),

    #"Added Month Start" =
        Table.AddColumn(
            #"Added Year Month Number",
            "Month Start",
            each Date.StartOfMonth([Date]),
            type date
        ),

    #"Added Month End" =
        Table.AddColumn(
            #"Added Month Start",
            "Month End",
            each Date.EndOfMonth([Date]),
            type date
        ),

    #"Added Quarter" =
        Table.AddColumn(
            #"Added Month End",
            "Quarter",
            each Date.QuarterOfYear([Date]),
            Int64.Type
        ),

    #"Added Quarter Full" =
        Table.AddColumn(
            #"Added Quarter",
            "Quarter Full",
            each "Q" & Number.ToText([Quarter]),
            type text
        ),

    #"Added Calendar Quarter Start" =
        Table.AddColumn(
            #"Added Quarter Full",
            "Calendar Quarter Start",
            each Date.StartOfQuarter([Date]),
            type date
        ),

    #"Added Calendar Quarter End" =
        Table.AddColumn(
            #"Added Calendar Quarter Start",
            "Calendar Quarter End",
            each Date.EndOfQuarter([Date]),
            type date
        ),

    #"Added Week of Year" =
        Table.AddColumn(
            #"Added Calendar Quarter End",
            "Week of Year",
            each Date.WeekOfYear([Date]),
            Int64.Type
        ),

    #"Added Week of Month" =
        Table.AddColumn(
            #"Added Week of Year",
            "Week of Month",
            each Date.WeekOfMonth([Date]),
            Int64.Type
        ),

    #"Added ISO Week Thursday" =
        Table.AddColumn(
            #"Added Week of Month",
            "_ISO Thursday",
            each Date.AddDays([Date], 3 - Date.DayOfWeek([Date], Day.Monday)),
            type date
        ),

    #"Added ISO Year" =
        Table.AddColumn(
            #"Added ISO Week Thursday",
            "ISO Year",
            each Date.Year([_ISO Thursday]),
            Int64.Type
        ),

    #"Added ISO Week Number" =
        Table.AddColumn(
            #"Added ISO Year",
            "ISO Week Number",
            each
                let
                    ISOYearStart = #date([ISO Year], 1, 4),
                    FirstISOThursday =
                        Date.AddDays(
                            ISOYearStart,
                            3 - Date.DayOfWeek(ISOYearStart, Day.Monday)
                        )
                in
                    Number.IntegerDivide(
                        Duration.Days([_ISO Thursday] - FirstISOThursday),
                        7
                    ) + 1,
            Int64.Type
        ),

    #"Added Year Week" =
        Table.AddColumn(
            #"Added ISO Week Number",
            "Year Week",
            each
                Number.ToText([ISO Year])
                & "-W"
                & Text.PadStart(Number.ToText([ISO Week Number]), 2, "0"),
            type text
        ),

    #"Removed ISO Helper" =
        Table.RemoveColumns(
            #"Added Year Week",
            {"_ISO Thursday"}
        ),

    #"Added Day" =
        Table.AddColumn(
            #"Removed ISO Helper",
            "Day",
            each Date.Day([Date]),
            Int64.Type
        ),

    #"Added Day of Week" =
        Table.AddColumn(
            #"Added Day",
            "Day of Week",
            each Date.DayOfWeek([Date]),
            Int64.Type
        ),

    #"Added Day of Year" =
        Table.AddColumn(
            #"Added Day of Week",
            "Day of Year",
            each Date.DayOfYear([Date]),
            Int64.Type
        ),

    #"Added Day Name" =
        Table.AddColumn(
            #"Added Day of Year",
            "Day Name",
            each Date.DayOfWeekName([Date]),
            type text
        ),

    #"Added Day Name Abb" =
        Table.AddColumn(
            #"Added Day Name",
            "Day Name Abb",
            each Text.Start([Day Name], 3),
            type text
        ),

    #"Added Month Yr" =
        Table.AddColumn(
            #"Added Day Name Abb",
            "Month Yr",
            each [Month Name Abb] & "-" & Text.End(Number.ToText([Year]), 2),
            type text
        ),


    // ============================================================
    // FINANCIAL YEAR START
    // ============================================================
    #"Added Financial Year Start" =
        Table.AddColumn(
            #"Added Month Yr",
            "Financial Year Start",
            each
                let
                    CurrentDate = [Date],
                    CurrentYear = Date.Year(CurrentDate),

                    OldStartThisYear =
                        #date(
                            CurrentYear,
                            OldFinancialYearStartMonth,
                            OldFinancialYearStartDay
                        ),

                    NewStartThisYear =
                        #date(
                            CurrentYear,
                            NewFinancialYearStartMonth,
                            NewFinancialYearStartDay
                        )
                in
                    if CurrentDate < FinancialYearChangeDate then
                        if CurrentDate >= OldStartThisYear then
                            OldStartThisYear
                        else
                            #date(
                                CurrentYear - 1,
                                OldFinancialYearStartMonth,
                                OldFinancialYearStartDay
                            )
                    else
                        if CurrentDate >= NewStartThisYear then
                            NewStartThisYear
                        else
                            #date(
                                CurrentYear - 1,
                                NewFinancialYearStartMonth,
                                NewFinancialYearStartDay
                            ),
            type date
        ),

    #"Added Financial Year End" =
        Table.AddColumn(
            #"Added Financial Year Start",
            "Financial Year End",
            each
                if [Financial Year Start] = #date(2025, 5, 1) then
                    #date(2026, 4, 29)
                else
                    Date.AddDays(
                        Date.AddYears([Financial Year Start], 1),
                        -1
                    ),
            type date
        ),

    #"Added Financial Year Short" =
        Table.AddColumn(
            #"Added Financial Year End",
            "Financial Year Short",
            each Date.Year([Financial Year End]),
            Int64.Type
        ),

    #"Added Financial Year Long" =
        Table.AddColumn(
            #"Added Financial Year Short",
            "Financial Year Long",
            each
                Text.End(Number.ToText(Date.Year([Financial Year Start])), 2)
                & "-"
                & Text.End(Number.ToText(Date.Year([Financial Year End])), 2),
            type text
        ),

    #"Added Financial Year Full" =
        Table.AddColumn(
            #"Added Financial Year Long",
            "Financial Year Full",
            each "FY " & [Financial Year Long],
            type text
        ),

    #"Added Financial Year Day Count" =
        Table.AddColumn(
            #"Added Financial Year Full",
            "Financial Year Day Count",
            each Duration.Days([Financial Year End] - [Financial Year Start]) + 1,
            Int64.Type
        ),

    #"Added Day of Financial Year" =
        Table.AddColumn(
            #"Added Financial Year Day Count",
            "Day of Financial Year",
            each Duration.Days([Date] - [Financial Year Start]) + 1,
            Int64.Type
        ),

    #"Added Days Remaining in Financial Year" =
        Table.AddColumn(
            #"Added Day of Financial Year",
            "Days Remaining in Financial Year",
            each Duration.Days([Financial Year End] - [Date]),
            Int64.Type
        ),

    #"Added Financial Week Number" =
        Table.AddColumn(
            #"Added Days Remaining in Financial Year",
            "Financial Week Number",
            each
                Number.IntegerDivide(
                    Duration.Days([Date] - [Financial Year Start]),
                    7
                ) + 1,
            Int64.Type
        ),


    // ============================================================
    // FINANCIAL MONTH
    // ============================================================
    #"Added Financial Month" =
        Table.AddColumn(
            #"Added Financial Week Number",
            "FInancial Month",
            each
                let
                    FYStart = [Financial Year Start],
                    CurrentDate = [Date],

                    ApproxMonths =
                        (Date.Year(CurrentDate) - Date.Year(FYStart)) * 12
                        + Date.Month(CurrentDate)
                        - Date.Month(FYStart),

                    MonthStartCandidate =
                        Date.AddMonths(FYStart, ApproxMonths),

                    FinancialMonth =
                        if CurrentDate < MonthStartCandidate then
                            ApproxMonths
                        else
                            ApproxMonths + 1
                in
                    FinancialMonth,
            Int64.Type
        ),

    #"Added Financial Month Start" =
        Table.AddColumn(
            #"Added Financial Month",
            "Financial Month Start",
            each
                Date.AddMonths(
                    [Financial Year Start],
                    [FInancial Month] - 1
                ),
            type date
        ),

    #"Added Financial Month End" =
        Table.AddColumn(
            #"Added Financial Month Start",
            "Financial Month End",
            each
                let
                    PeriodEnd =
                        Date.AddDays(
                            Date.AddMonths(
                                [Financial Year Start],
                                [FInancial Month]
                            ),
                            -1
                        )
                in
                    if PeriodEnd > [Financial Year End] then
                        [Financial Year End]
                    else
                        PeriodEnd,
            type date
        ),

    #"Added Day of Financial Month" =
        Table.AddColumn(
            #"Added Financial Month End",
            "Day of Financial Month",
            each Duration.Days([Date] - [Financial Month Start]) + 1,
            Int64.Type
        ),


    // ============================================================
    // FINANCIAL QUARTER
    // ============================================================
    #"Added Financial Quarter" =
        Table.AddColumn(
            #"Added Day of Financial Month",
            "Financial Quarter",
            each Number.RoundUp([FInancial Month] / 3),
            Int64.Type
        ),

    #"Added Financial Quarter Full" =
        Table.AddColumn(
            #"Added Financial Quarter",
            "Financial Quarter Full",
            each "Q" & Number.ToText([Financial Quarter]),
            type text
        ),

    #"Added Quarter Start Date" =
        Table.AddColumn(
            #"Added Financial Quarter Full",
            "Quarter Start Date",
            each
                Date.AddMonths(
                    [Financial Year Start],
                    ([Financial Quarter] - 1) * 3
                ),
            type date
        ),

    #"Added Quarter End" =
        Table.AddColumn(
            #"Added Quarter Start Date",
            "Quarter End",
            each
                let
                    NormalQuarterEnd =
                        Date.AddDays(
                            Date.AddMonths([Quarter Start Date], 3),
                            -1
                        )
                in
                    if NormalQuarterEnd > [Financial Year End] then
                        [Financial Year End]
                    else
                        NormalQuarterEnd,
            type date
        ),

    #"Added Day of Financial Quarter" =
        Table.AddColumn(
            #"Added Quarter End",
            "Day of Financial Quarter",
            each Duration.Days([Date] - [Quarter Start Date]) + 1,
            Int64.Type
        ),


    // ============================================================
    // DISPLAY / SORT COLUMNS
    // ============================================================
    #"Added Quarter & Year" =
        Table.AddColumn(
            #"Added Day of Financial Quarter",
            "Quarter & Year",
            each [Financial Quarter Full] & " " & [Financial Year Long],
            type text
        ),

    #"Added Month & Year" =
        Table.AddColumn(
            #"Added Quarter & Year",
            "Month & Year",
            each [Month Name Abb] & " " & [Financial Year Long],
            type text
        ),

    #"Added Month & Year Number" =
        Table.AddColumn(
            #"Added Month & Year",
            "Month & Year Number",
            each
                Number.FromText(
                    Text.End(Number.ToText([Financial Year Short]), 2)
                    &
                    Text.PadStart(
                        Number.ToText([FInancial Month]),
                        2,
                        "0"
                    )
                ),
            Int64.Type
        ),


    // ============================================================
    // CURRENT PERIOD FLAGS
    // ============================================================
    #"Added Is Today" =
        Table.AddColumn(
            #"Added Month & Year Number",
            "Is Today",
            each [Date] = Today,
            type logical
        ),

    #"Added Is Yesterday" =
        Table.AddColumn(
            #"Added Is Today",
            "Is Yesterday",
            each [Date] = Date.AddDays(Today, -1),
            type logical
        ),

    #"Added Is Current Week" =
        Table.AddColumn(
            #"Added Is Yesterday",
            "Is Current Week",
            each
                [Date] >= Date.StartOfWeek(Today, Day.Monday)
                and [Date] <= Date.EndOfWeek(Today, Day.Monday),
            type logical
        ),

    #"Added Is Current Month" =
        Table.AddColumn(
            #"Added Is Current Week",
            "Is Current Month",
            each
                Date.Year([Date]) = Date.Year(Today)
                and Date.Month([Date]) = Date.Month(Today),
            type logical
        ),

    #"Added Is Current Financial Month" =
        Table.AddColumn(
            #"Added Is Current Month",
            "Is Current Financial Month",
            each
                Today >= [Financial Month Start]
                and Today <= [Financial Month End],
            type logical
        ),

    #"Added Is Current Financial Quarter" =
        Table.AddColumn(
            #"Added Is Current Financial Month",
            "Is Current Financial Quarter",
            each
                Today >= [Quarter Start Date]
                and Today <= [Quarter End],
            type logical
        ),

    #"Added Is Current Financial Year" =
        Table.AddColumn(
            #"Added Is Current Financial Quarter",
            "Is Current Financial Year",
            each
                Today >= [Financial Year Start]
                and Today <= [Financial Year End],
            type logical
        ),

    #"Added Is Previous Financial Year" =
        Table.AddColumn(
            #"Added Is Current Financial Year",
            "Is Previous Financial Year",
            each
                let
                    CurrentFYStart =
                        if Today < FinancialYearChangeDate then
                            if Today >= #date(Date.Year(Today), OldFinancialYearStartMonth, OldFinancialYearStartDay) then
                                #date(Date.Year(Today), OldFinancialYearStartMonth, OldFinancialYearStartDay)
                            else
                                #date(Date.Year(Today) - 1, OldFinancialYearStartMonth, OldFinancialYearStartDay)
                        else
                            if Today >= #date(Date.Year(Today), NewFinancialYearStartMonth, NewFinancialYearStartDay) then
                                #date(Date.Year(Today), NewFinancialYearStartMonth, NewFinancialYearStartDay)
                            else
                                #date(Date.Year(Today) - 1, NewFinancialYearStartMonth, NewFinancialYearStartDay),

                    PreviousFYEnd = Date.AddDays(CurrentFYStart, -1)
                in
                    [Financial Year End] = PreviousFYEnd,
            type logical
        ),


    // ============================================================
    // ENGLAND & WALES BANK HOLIDAYS
    // ============================================================
    #"Added Bank Holiday Name" =
        Table.AddColumn(
            #"Added Is Previous Financial Year",
            "Bank Holiday Name",
            each
                let
                    D = [Date],
                    Y = [Year],
                    Easter = EasterSunday(Y),
                    GoodFriday = Date.AddDays(Easter, -2),
                    EasterMonday = Date.AddDays(Easter, 1),
                    NewYearBH = NewYearsDayBankHoliday(Y),
                    EarlyMayBH = NthWeekdayOfMonth(Y, 5, 0, 1),
                    SpringBH = LastWeekdayOfMonth(Y, 5, 0),
                    SummerBH = LastWeekdayOfMonth(Y, 8, 0),
                    ChristmasBH = ChristmasBankHoliday(Y),
                    BoxingBH = BoxingDayBankHoliday(Y),

                    // Known one-off England & Wales bank holidays in the table range.
                    OneOffName =
                        if D = #date(2011, 4, 29) then "Royal Wedding"
                        else if D = #date(2012, 6, 4) then "Queen's Diamond Jubilee"
                        else if D = #date(2012, 6, 5) then "Spring Bank Holiday"
                        else if D = #date(2022, 6, 2) then "Spring Bank Holiday"
                        else if D = #date(2022, 6, 3) then "Queen's Platinum Jubilee"
                        else if D = #date(2022, 9, 19) then "State Funeral of Queen Elizabeth II"
                        else if D = #date(2023, 5, 8) then "Coronation of King Charles III"
                        else null,

                    // Years where the normal late-May Spring Bank Holiday was moved.
                    IsMovedSpringYear = List.Contains({2002, 2012, 2022}, Y)
                in
                    if OneOffName <> null then OneOffName
                    else if D = NewYearBH then "New Year's Day"
                    else if D = GoodFriday then "Good Friday"
                    else if D = EasterMonday then "Easter Monday"
                    else if D = EarlyMayBH then "Early May Bank Holiday"
                    else if (not IsMovedSpringYear) and D = SpringBH then "Spring Bank Holiday"
                    else if D = SummerBH then "Summer Bank Holiday"
                    else if D = ChristmasBH then "Christmas Day"
                    else if D = BoxingBH then "Boxing Day"
                    else null,
            type text
        ),

    #"Added Is Bank Holiday" =
        Table.AddColumn(
            #"Added Bank Holiday Name",
            "Is Bank Holiday",
            each [Bank Holiday Name] <> null,
            type logical
        ),


    // ============================================================
    // WORKING DAY
    // ============================================================
    #"Added Is Working Day" =
        Table.AddColumn(
            #"Added Is Bank Holiday",
            "Is Working Day",
            each
                not List.Contains({5, 6}, [Day of Week])
                and not [Is Bank Holiday]
                and not List.Contains(AdditionalNonWorkingDates, [Date]),
            type logical
        ),

    #"Added Is a Working Day" =
        Table.AddColumn(
            #"Added Is Working Day",
            "Is a Working Day",
            each if [Is Working Day] then 1 else 0,
            Int64.Type
        ),


    // ============================================================
    // FINAL COLUMN ORDER
    // ============================================================
    #"Reordered Columns" =
        Table.ReorderColumns(
            #"Added Is a Working Day",
            {
                "Date",
                "Year",
                "Year Month",
                "Year Month Number",
                "Month Start",
                "Month End",
                "Quarter",
                "Quarter Full",
                "Calendar Quarter Start",
                "Calendar Quarter End",
                "ISO Year",
                "ISO Week Number",
                "Year Week",

                "Financial Year Short",
                "Financial Year Long",
                "Financial Year Full",
                "Financial Year Start",
                "Financial Year End",
                "Financial Year Day Count",
                "Day of Financial Year",
                "Days Remaining in Financial Year",
                "Financial Week Number",

                "Financial Quarter",
                "Financial Quarter Full",
                "Quarter Start Date",
                "Quarter End",
                "Day of Financial Quarter",
                "Quarter & Year",

                "Month",
                "FInancial Month",
                "Financial Month Start",
                "Financial Month End",
                "Day of Financial Month",
                "Month Name",
                "Month Name Abb",
                "Month Yr",
                "Month & Year",
                "Month & Year Number",

                "Week of Year",
                "Week of Month",
                "Day",
                "Day of Week",
                "Day of Year",
                "Day Name",
                "Day Name Abb",

                "Bank Holiday Name",
                "Is Bank Holiday",
                "Is Working Day",
                "Is a Working Day",

                "Is Today",
                "Is Yesterday",
                "Is Current Week",
                "Is Current Month",
                "Is Current Financial Month",
                "Is Current Financial Quarter",
                "Is Current Financial Year",
                "Is Previous Financial Year"
            }
        )

in
    #"Reordered Columns"

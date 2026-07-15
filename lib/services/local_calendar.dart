/// Shared local-calendar (year/month/day) arithmetic used by every streak
/// and weekly-window calculation in the app, so "a day" always means the
/// same thing (a calendar field, not a rolling 24h Duration) regardless of
/// which service is doing the counting.
library;

/// Strips the time-of-day, keeping only the local calendar date.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Adds [days] (may be negative) to a date-only [DateTime] using calendar
/// fields rather than a fixed Duration, so it stays exactly at local
/// midnight across DST transitions instead of drifting to 23:00/01:00.
DateTime addDays(DateTime dateOnlyValue, int days) =>
    DateTime(dateOnlyValue.year, dateOnlyValue.month, dateOnlyValue.day + days);

/// The Monday (local calendar) of the week containing [dateOnlyValue].
DateTime startOfWeek(DateTime dateOnlyValue) =>
    addDays(dateOnlyValue, -(dateOnlyValue.weekday - 1));

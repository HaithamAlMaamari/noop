import Foundation

/// Personal build: the working week this build is set up for (Oman / GCC).
///
/// The alarm screens laid days out Monday-first and called Mon–Fri "Weekdays" and Sat–Sun "Weekends",
/// which is the wrong week in Oman: the working week is Sunday–Thursday and the weekend Friday–Saturday.
/// Calendar weekday numbers (1 = Sunday … 7 = Saturday) are region-independent, so the alarm itself was
/// always right; this only fixes how the days are ordered and named. One place to change it back.
enum PersonalRegion {
    /// Day chips in reading order: Sunday first, the weekend at the end.
    static let weekdayOrder = [1, 2, 3, 4, 5, 6, 7]
    /// Sunday–Thursday.
    static let workDays: Set<Int> = [1, 2, 3, 4, 5]
    /// Friday–Saturday.
    static let weekendDays: Set<Int> = [6, 7]
}

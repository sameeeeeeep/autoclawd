import Foundation

// MARK: - CronEvaluator
//
// Pure stateless cron expression evaluator. Supports 5-field cron:
//   minute hour dayOfMonth month dayOfWeek
//
// Each field accepts:
//   *          any value
//   5          exact value
//   1,3,5      comma-separated list
//   1-5        range
//   */5        step (every N)
//   1-5/2      range with step
//
// DayOfWeek: 0=Sun, 1=Mon … 6=Sat (also accepts 7 = Sun for compat)
// All evaluation is done in local timezone.

enum CronEvaluator {

    // MARK: - Public API

    /// Compute the next fire date after `after`. Returns nil if the expression is invalid.
    static func nextDate(from expression: String, after: Date = Date()) -> Date? {
        guard let fields = parse(expression) else { return nil }

        var cal = Calendar.current
        cal.timeZone = TimeZone.current

        // Start one minute after `after`
        guard let start = cal.date(byAdding: .minute, value: 1, to: after) else { return nil }

        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: start)
        comps.second = 0

        // Search up to 4 years (prevents infinite loop on invalid expressions)
        let limit = 366 * 24 * 60 * 4

        for _ in 0..<limit {
            guard let year  = comps.year,
                  let month = comps.month,
                  let day   = comps.day,
                  let hour  = comps.hour,
                  let min   = comps.minute,
                  let weekdayVal = comps.weekday   // 1=Sun…7=Sat in Calendar
            else { return nil }

            let dow = weekdayVal - 1   // convert to 0-based (0=Sun)

            let monthMatch = fields.month.matches(month)
            let domMatch   = fields.dayOfMonth.matches(day)
            let dowMatch   = fields.dayOfWeek.matches(dow)

            // dayOfMonth and dayOfWeek: both wildcard → AND logic, one non-wildcard → OR logic
            let dayMatch: Bool
            if fields.dayOfMonth.isWildcard && fields.dayOfWeek.isWildcard {
                dayMatch = true
            } else if fields.dayOfMonth.isWildcard {
                dayMatch = dowMatch
            } else if fields.dayOfWeek.isWildcard {
                dayMatch = domMatch
            } else {
                dayMatch = domMatch || dowMatch  // traditional cron OR semantics
            }

            guard monthMatch else {
                // Skip to first day of next month
                comps = DateComponents(year: year, month: month + 1, day: 1, hour: 0, minute: 0, second: 0)
                normalizeComps(&comps, cal: cal)
                continue
            }

            guard dayMatch else {
                // Skip to next day
                comps = DateComponents(year: year, month: month, day: day + 1, hour: 0, minute: 0, second: 0)
                normalizeComps(&comps, cal: cal)
                continue
            }

            guard fields.hour.matches(hour) else {
                // Skip to next valid hour
                let nextHour = (fields.hour.nextValue(after: hour) ?? -1)
                if nextHour == -1 || nextHour <= hour {
                    comps = DateComponents(year: year, month: month, day: day + 1, hour: 0, minute: 0, second: 0)
                } else {
                    comps = DateComponents(year: year, month: month, day: day, hour: nextHour, minute: 0, second: 0)
                }
                normalizeComps(&comps, cal: cal)
                continue
            }

            guard fields.minute.matches(min) else {
                let nextMin = fields.minute.nextValue(after: min) ?? -1
                if nextMin == -1 || nextMin <= min {
                    comps = DateComponents(year: year, month: month, day: day, hour: hour + 1, minute: 0, second: 0)
                } else {
                    comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: nextMin, second: 0)
                }
                normalizeComps(&comps, cal: cal)
                continue
            }

            // All fields matched
            comps.second = 0
            return cal.date(from: comps)
        }
        return nil
    }

    /// Returns true if the expression parses without errors.
    static func isValid(_ expression: String) -> Bool {
        parse(expression) != nil
    }

    /// Human-readable description. Falls back to the raw expression on failure.
    static func humanReadable(_ expression: String) -> String {
        guard let fields = parse(expression) else { return expression }
        return describe(fields: fields, raw: expression)
    }

    // MARK: - Internal Types

    private struct CronFields {
        let minute:     CronField
        let hour:       CronField
        let dayOfMonth: CronField
        let month:      CronField
        let dayOfWeek:  CronField
    }

    struct CronField {
        let values: Set<Int>?   // nil = wildcard (*)
        let range: ClosedRange<Int>

        var isWildcard: Bool { values == nil }

        func matches(_ n: Int) -> Bool {
            guard let vals = values else { return true }
            return vals.contains(n)
        }

        /// First value in the set strictly greater than `n`, or nil if none.
        func nextValue(after n: Int) -> Int? {
            guard let vals = values else { return (n + 1 <= range.upperBound) ? n + 1 : nil }
            return vals.sorted().first { $0 > n }
        }
    }

    // MARK: - Parser

    private static func parse(_ expression: String) -> CronFields? {
        let parts = expression.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard parts.count == 5 else { return nil }

        guard let minute     = parseField(parts[0], range: 0...59),
              let hour       = parseField(parts[1], range: 0...23),
              let dayOfMonth = parseField(parts[2], range: 1...31),
              let month      = parseField(parts[3], range: 1...12),
              let dayOfWeek  = parseField(parts[4], range: 0...6, aliases: Self.dowAliases)
        else { return nil }

        return CronFields(minute: minute, hour: hour, dayOfMonth: dayOfMonth,
                          month: month, dayOfWeek: dayOfWeek)
    }

    private static let dowAliases: [String: Int] = [
        "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6
    ]

    private static func parseField(_ token: String,
                                   range: ClosedRange<Int>,
                                   aliases: [String: Int] = [:]) -> CronField? {
        // Wildcard
        if token == "*" { return CronField(values: nil, range: range) }

        var result: Set<Int> = []
        let segments = token.components(separatedBy: ",")
        for seg in segments {
            if let val = resolveValues(seg, range: range, aliases: aliases) {
                result.formUnion(val)
            } else {
                return nil
            }
        }
        return CronField(values: result.isEmpty ? nil : result, range: range)
    }

    private static func resolveValues(_ seg: String,
                                      range: ClosedRange<Int>,
                                      aliases: [String: Int]) -> Set<Int>? {
        var result: Set<Int> = []

        // Step: x/y or x-y/z or */y
        if seg.contains("/") {
            let stepParts = seg.components(separatedBy: "/")
            guard stepParts.count == 2, let step = Int(stepParts[1]), step > 0 else { return nil }
            let base = stepParts[0]

            let startRange: ClosedRange<Int>
            if base == "*" {
                startRange = range
            } else if base.contains("-") {
                guard let r = parseRange(base, range: range, aliases: aliases) else { return nil }
                startRange = r
            } else {
                guard let v = parseValue(base, aliases: aliases), range.contains(v) else { return nil }
                startRange = v...range.upperBound
            }

            var cur = startRange.lowerBound
            while cur <= startRange.upperBound {
                result.insert(cur)
                cur += step
            }
            return result
        }

        // Range: x-y
        if seg.contains("-") {
            guard let r = parseRange(seg, range: range, aliases: aliases) else { return nil }
            for v in r { result.insert(v) }
            return result
        }

        // Single value
        guard let v = parseValue(seg, aliases: aliases), range.contains(v) else { return nil }
        // Normalize 7 → 0 for Sunday
        result.insert(v == 7 ? 0 : v)
        return result
    }

    private static func parseRange(_ s: String,
                                   range: ClosedRange<Int>,
                                   aliases: [String: Int]) -> ClosedRange<Int>? {
        let parts = s.components(separatedBy: "-")
        guard parts.count == 2,
              let lo = parseValue(parts[0], aliases: aliases),
              let hi = parseValue(parts[1], aliases: aliases),
              lo <= hi,
              range.contains(lo), range.contains(hi)
        else { return nil }
        return lo...hi
    }

    private static func parseValue(_ s: String, aliases: [String: Int]) -> Int? {
        if let n = Int(s) { return n }
        return aliases[s.lowercased()]
    }

    // MARK: - Normalize DateComponents

    private static func normalizeComps(_ comps: inout DateComponents, cal: Calendar) {
        // Convert back and forth through a Date to normalize overflow (e.g. day 32 → next month)
        if let d = cal.date(from: comps) {
            let normalized = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
            comps = normalized
            comps.weekday = cal.component(.weekday, from: d)
        }
    }

    // MARK: - Human Readable

    private static func describe(fields: CronFields, raw: String) -> String {
        let timeStr = describeTime(min: fields.minute, hr: fields.hour)
        let dayStr  = describeDays(dom: fields.dayOfMonth, dow: fields.dayOfWeek, month: fields.month)
        return [timeStr, dayStr].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func describeTime(min: CronField, hr: CronField) -> String {
        if min.isWildcard && hr.isWildcard { return "Every minute" }
        if min.isWildcard { return "Every minute" }

        let hrStr: String
        if hr.isWildcard {
            hrStr = "every hour"
        } else if let h = hr.values?.first, hr.values?.count == 1 {
            let ampm = h < 12 ? "AM" : "PM"
            let h12  = h == 0 ? 12 : (h > 12 ? h - 12 : h)
            let mStr = min.values?.first.map { String(format: ":%02d", $0) } ?? ":00"
            return "At \(h12)\(mStr) \(ampm)"
        } else {
            hrStr = "at select hours"
        }

        if let m = min.values?.first, min.values?.count == 1 {
            return m == 0 ? "On the hour (\(hrStr))" : "At :\(String(format: "%02d", m)) (\(hrStr))"
        }
        return "Periodically (\(hrStr))"
    }

    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let monthNames = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static func describeDays(dom: CronField, dow: CronField, month: CronField) -> String {
        var parts: [String] = []

        if !month.isWildcard, let months = month.values {
            let names = months.sorted().compactMap { $0 < monthNames.count ? monthNames[$0] : nil }
            parts.append("in \(names.joined(separator: "/"))")
        }

        if !dow.isWildcard, let days = dow.values {
            if days == Set(1...5) {
                parts.append("on weekdays")
            } else if days == Set([0, 6]) {
                parts.append("on weekends")
            } else {
                let names = days.sorted().compactMap { $0 < dayNames.count ? dayNames[$0] : nil }
                parts.append("on \(names.joined(separator: "/"))")
            }
        } else if !dom.isWildcard, let days = dom.values {
            if days.count == 1, let d = days.first {
                let suffix = daySuffix(d)
                parts.append("on the \(d)\(suffix)")
            } else {
                parts.append("on selected days")
            }
        } else if dow.isWildcard && dom.isWildcard {
            parts.append("daily")
        }

        return parts.joined(separator: " ")
    }

    private static func daySuffix(_ n: Int) -> String {
        switch n % 10 {
        case 1 where n != 11: return "st"
        case 2 where n != 12: return "nd"
        case 3 where n != 13: return "rd"
        default: return "th"
        }
    }
}

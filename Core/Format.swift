import Foundation

enum Format {
    /// "42m", "1h 18m", "11h".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int((seconds / 60).rounded(.down)))
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Minutes as "1h 15", "45m" — compact, for wake-window ranges.
    static func minutes(_ value: Double) -> String {
        let total = Int(value.rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : String(format: "%dh%02d", h, m)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func age(days: Int) -> String {
        switch days {
        case ..<14: return "\(days) d"
        case ..<(7 * 16): return "\(days / 7) wk"
        case ..<730: return "\(Int(Double(days) / 30.44)) mo"
        default: return "\(days / 365) yr"
        }
    }

    static func volume(ml: Double, unit: VolumeUnit) -> String {
        switch unit {
        case .ml: return "\(Int(ml.rounded())) ml"
        case .oz: return String(format: "%.1f oz", ml / VolumeUnit.mlPerOz)
        }
    }

    /// "Breast · L · 14m", "Bottle · 120 ml", "Solids".
    static func feedLabel(_ e: Entry, unit: VolumeUnit, now: Date = Date()) -> String {
        switch e.feedMethod ?? .breast {
        case .breast:
            var parts = ["Breast"]
            if let s = e.side { parts.append(s.short) }
            parts.append(duration(e.duration(at: now)))
            return parts.joined(separator: " · ")
        case .bottle:
            return "Bottle · " + volume(ml: e.amountML ?? 0, unit: unit)
        case .solids:
            return "Solids"
        }
    }

    static func title(_ e: Entry, unit: VolumeUnit, now: Date = Date()) -> String {
        switch e.kind {
        case .sleep: return "Sleep · " + duration(e.duration(at: now))
        case .feed: return feedLabel(e, unit: unit, now: now)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()
}

import Foundation

/// The next recommended time to put the baby down.
struct NapPrediction: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case nap, bedtime }
    enum Phase: Sendable { case upcoming, open, late }

    var kind: Kind
    /// 1-based number of the coming nap (for `.bedtime`: naps taken today).
    var napNumber: Int
    var awakeSince: Date
    var target: Date
    var windowStart: Date
    var windowEnd: Date
    /// Age-typical range for this window, minutes.
    var typicalMinutes: ClosedRange<Double>
    /// The wake window actually used, minutes.
    var targetMinutes: Double
    /// True once the baby's own recent windows shifted the age default.
    var personalized: Bool
    /// True when the previous nap was short and the window was shortened.
    var shortNapAdjusted: Bool
    var bandLabel: String

    func phase(at now: Date) -> Phase {
        if now < windowStart { return .upcoming }
        if now <= windowEnd { return .open }
        return .late
    }

    var title: String { kind == .bedtime ? "Bedtime" : "Nap \(napNumber)" }
}

/// Where the current awake period sits within the baby's day.
enum DayPosition: Equatable {
    /// Wake window `index` of the day: 0 = morning wake → first nap.
    case window(index: Int, previousNap: Entry?)
    /// Awake during the night (a night waking) — no nap window applies.
    case night
}

/// Predicts the next nap / bedtime window from age-typical wake windows,
/// adjusted by (a) the baby's own last 7 days of wake windows that led to a
/// good sleep and (b) a short previous nap.
struct NapPredictor {
    var calendar: Calendar = .current
    var historyDays: Double = 7

    /// A nap shorter than this is "short": the next window is shortened.
    static let goodNapMinutes = 40.0
    static let shortNapFactor = 0.85
    /// Personalization needs this many usable samples before it kicks in.
    static let minSamples = 3

    // MARK: - Day structure

    /// Sleeps starting 19:00–06:00 belong to the night, as does a sleep of
    /// 3h+ starting from 17:00.
    func isNightSleep(_ e: Entry) -> Bool {
        let h = calendar.component(.hour, from: e.start)
        if h >= 19 || h < 6 { return true }
        if h >= 17, let end = e.end, end.timeIntervalSince(e.start) >= 3 * 3600 { return true }
        return false
    }

    /// Position of the wake window that starts when `sleep` ends.
    func position(after sleep: Entry, in sleeps: [Entry]) -> DayPosition {
        guard let wake = sleep.end else { return .night }

        if isNightSleep(sleep) {
            let h = calendar.component(.hour, from: wake)
            return (4..<12).contains(h) ? .window(index: 0, previousNap: nil) : .night
        }

        // A nap: count the naps since this morning's wake-up, including it.
        let morningWake = sleeps
            .filter { isNightSleep($0) }
            .compactMap(\.end)
            .filter { $0 <= sleep.start && sleep.start.timeIntervalSince($0) < 16 * 3600 }
            .max() ?? calendar.startOfDay(for: sleep.start)

        let napsToday = sleeps.filter { s in
            guard let end = s.end, !isNightSleep(s) else { return false }
            return s.start >= morningWake && s.start <= sleep.start && end <= wake
        }
        return .window(index: max(1, napsToday.count), previousNap: sleep)
    }

    // MARK: - Prediction

    func predict(_ data: LogData, now: Date) -> NapPrediction? {
        guard let profile = data.profile, data.activeSleep == nil else { return nil }
        let sleeps = data.completedSleeps.sorted { $0.start < $1.start }
        guard let last = sleeps.max(by: { $0.end! < $1.end! }), let wake = last.end else { return nil }
        // Ignore future-dated entries and logs that went stale (forgot to log).
        guard wake <= now.addingTimeInterval(60), now.timeIntervalSince(wake) < 12 * 3600 else { return nil }
        guard case let .window(rawIndex, previousNap) = position(after: last, in: sleeps) else { return nil }

        let age = profile.ageInDays(at: now, calendar: calendar)
        let band = WakeWindows.band(forAgeDays: age)
        let (factor, samples) = personalFactor(sleeps: sleeps, profile: profile, now: now)
        let personalized = samples >= Self.minSamples
        let shortNap = previousNap.map { $0.duration() / 60 < Self.goodNapMinutes } ?? false

        func minutes(forIndex index: Int) -> (ClosedRange<Double>, Double) {
            let typical = WakeWindows.range(for: band, index: index)
            var m = typical.mid
            if personalized { m *= factor }
            if shortNap { m *= Self.shortNapFactor }
            m = min(max(m, typical.lowerBound * 0.8), typical.upperBound * 1.2)
            return (typical, m)
        }

        var index = min(rawIndex, band.naps)
        var (typical, m) = minutes(forIndex: index)
        // Past 3 months, a nap that would start after 18:00 becomes bedtime.
        if index < band.naps, age >= 91,
           calendar.component(.hour, from: wake.addingTimeInterval(m * 60)) >= 18 {
            index = band.naps
            (typical, m) = minutes(forIndex: index)
        }

        let target = wake.addingTimeInterval(m * 60)
        let half = min(max(m * 0.08, 10), 20) * 60
        return NapPrediction(
            kind: index >= band.naps ? .bedtime : .nap,
            napNumber: index >= band.naps ? min(rawIndex, band.naps) : index + 1,
            awakeSince: wake,
            target: target,
            windowStart: target.addingTimeInterval(-half),
            windowEnd: target.addingTimeInterval(half),
            typicalMinutes: typical,
            targetMinutes: m,
            personalized: personalized,
            shortNapAdjusted: shortNap,
            bandLabel: band.label
        )
    }

    /// How the baby's recent wake windows compare to the age default:
    /// the median observed/expected ratio over the last `historyDays`,
    /// using only windows that ended in a good sleep, blended in with a
    /// weight of up to 50% as samples accumulate.
    func personalFactor(sleeps: [Entry], profile: BabyProfile, now: Date) -> (factor: Double, samples: Int) {
        let since = now.addingTimeInterval(-historyDays * 86400)
        var ratios: [Double] = []
        for (i, a) in sleeps.enumerated() where i + 1 < sleeps.count {
            let b = sleeps[i + 1]
            guard let aEnd = a.end, aEnd >= since, let bEnd = b.end else { continue }
            let window = b.start.timeIntervalSince(aEnd) / 60
            guard window >= 15, window <= 8 * 60 else { continue }
            guard case let .window(index, _) = position(after: a, in: sleeps) else { continue }
            let nextSleepMinutes = bEnd.timeIntervalSince(b.start) / 60
            guard isNightSleep(b) || nextSleepMinutes >= Self.goodNapMinutes else { continue }
            let band = WakeWindows.band(forAgeDays: profile.ageInDays(at: aEnd, calendar: calendar))
            let expected = WakeWindows.range(for: band, index: min(index, band.naps)).mid
            ratios.append(window / expected)
        }
        ratios = Array(ratios.suffix(20))
        guard ratios.count >= Self.minSamples else { return (1, ratios.count) }
        let sorted = ratios.sorted()
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            : sorted[sorted.count / 2]
        let clamped = min(max(median, 0.8), 1.25)
        let weight = Double(min(ratios.count, 10)) / 20
        return (1 + weight * (clamped - 1), ratios.count)
    }
}

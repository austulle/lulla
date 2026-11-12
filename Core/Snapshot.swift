import Foundation

/// Everything a screen, widget or Siri answer needs, computed once from the
/// log at a given moment.
struct LullSnapshot: Hashable, Sendable {
    enum Mood: String, Sendable { case awake, asleep, feeding, night }

    var now: Date
    var hasProfile: Bool
    var babyName: String
    var ageText: String
    var sleepStart: Date?
    var feedStart: Date?
    var feedSide: BreastSide?
    var awakeSince: Date?
    var prediction: NapPrediction?
    var isNightWaking: Bool
    var lastFeed: Entry?
    var nextSide: BreastSide
    var feedingStyle: FeedingStyle
    var volumeUnit: VolumeUnit
    var todaySleep: TimeInterval
    var todayNaps: Int
    var todayFeeds: Int
    var todayDiapers: Int

    var isAsleep: Bool { sleepStart != nil }
    var isFeeding: Bool { feedStart != nil }

    var mood: Mood {
        if isFeeding { return .feeding }
        if isAsleep || isNightWaking { return Self.isNightHour(now) ? .night : .asleep }
        return Self.isNightHour(now) ? .night : .awake
    }

    static func isNightHour(_ date: Date, calendar: Calendar = .current) -> Bool {
        let h = calendar.component(.hour, from: date)
        return h >= 20 || h < 6
    }

    static func make(_ data: LogData, now: Date, calendar: Calendar = .current) -> LullSnapshot {
        let predictor = NapPredictor(calendar: calendar)
        let prediction = predictor.predict(data, now: now)
        let lastSleep = data.lastCompletedSleep
        let awakeSince = data.activeSleep == nil ? lastSleep?.end : nil

        var nightWaking = false
        if prediction == nil, data.activeSleep == nil, let last = lastSleep {
            let sleeps = data.completedSleeps.sorted { $0.start < $1.start }
            nightWaking = predictor.position(after: last, in: sleeps) == .night
        }

        // "Today" = since local midnight; sleep overlapping midnight is clipped.
        let dayStart = calendar.startOfDay(for: now)
        let today = DateInterval(start: dayStart, end: max(now, dayStart))
        let todays = data.entries(overlapping: today, now: now)
        let sleepToday = todays.filter { $0.kind == .sleep }.reduce(0.0) { sum, e in
            let s = max(e.start, dayStart), t = min(e.end ?? now, now)
            return sum + max(0, t.timeIntervalSince(s))
        }
        let napsToday = todays.filter {
            $0.kind == .sleep && $0.start >= dayStart && !predictor.isNightSleep($0)
        }.count

        let profile = data.profile
        return LullSnapshot(
            now: now,
            hasProfile: profile != nil,
            babyName: profile?.displayName ?? "Baby",
            ageText: profile.map { Format.age(days: $0.ageInDays(at: now, calendar: calendar)) } ?? "",
            sleepStart: data.activeSleep?.start,
            feedStart: data.activeFeed?.start,
            feedSide: data.activeFeed?.side,
            awakeSince: awakeSince,
            prediction: prediction,
            isNightWaking: nightWaking,
            lastFeed: data.lastFeed,
            nextSide: data.suggestedSide,
            feedingStyle: profile?.feedingStyle ?? .breast,
            volumeUnit: profile?.volumeUnit ?? .ml,
            todaySleep: sleepToday,
            todayNaps: napsToday,
            todayFeeds: todays.filter { $0.kind == .feed && $0.start >= dayStart }.count,
            todayDiapers: todays.filter { $0.kind == .diaper && $0.start >= dayStart }.count
        )
    }

    // MARK: - Phrases shared by app, widgets and Siri

    var lastFeedPhrase: String {
        guard let f = lastFeed else { return "No feeds yet" }
        if f.isRunning { return "Feeding now" }
        return "\(Format.duration(now.timeIntervalSince(f.end ?? f.start))) ago"
    }

    var napPhrase: String {
        if let s = sleepStart { return "Asleep for \(Format.duration(now.timeIntervalSince(s)))" }
        if isNightWaking { return "Night waking" }
        guard let p = prediction else { return "Log a sleep to see the next window" }
        switch p.phase(at: now) {
        case .upcoming:
            return "\(p.title) window \(Format.time(p.windowStart))–\(Format.time(p.windowEnd))"
        case .open:
            return "\(p.title) window is open until \(Format.time(p.windowEnd))"
        case .late:
            return "Past the \(p.title.lowercased()) window — try soon"
        }
    }
}

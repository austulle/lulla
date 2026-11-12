import Foundation

// Pure data model — no UI imports, so it compiles into the app, the widget
// extension and the tests (and on Linux for the predictor tests).

enum EntryKind: String, Codable, CaseIterable, Sendable {
    case sleep, feed
}

enum FeedMethod: String, Codable, CaseIterable, Sendable {
    case breast, bottle, solids
}

enum BreastSide: String, Codable, CaseIterable, Sendable {
    case left, right

    var opposite: BreastSide { self == .left ? .right : .left }
    var short: String { self == .left ? "L" : "R" }
    var title: String { self == .left ? "Left" : "Right" }
}

enum BottleContent: String, Codable, CaseIterable, Sendable {
    case formula, breastMilk

    var title: String { self == .formula ? "Formula" : "Breast milk" }
}

/// One logged event. Timed events (sleep, breastfeeding) have `end == nil`
/// while their timer runs; instant events (bottle, solids) have
/// `end == start`. A running timer can be paused: `pausedAt` marks the
/// current pause and `pausedTotal` sums the finished ones, so the entry's
/// duration counts only the time the timer actually ran.
struct Entry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var kind: EntryKind
    var start: Date
    var end: Date?
    var feedMethod: FeedMethod?
    var side: BreastSide?
    var amountML: Double?
    var bottleContent: BottleContent?
    var note: String?
    var pausedAt: Date?
    var pausedTotal: TimeInterval?

    var isRunning: Bool { end == nil }
    var isPaused: Bool { end == nil && pausedAt != nil }

    /// Time the timer ran, excluding pauses.
    func duration(at now: Date = Date()) -> TimeInterval {
        let stop = end ?? now
        var paused = pausedTotal ?? 0
        if end == nil, let p = pausedAt { paused += max(0, now.timeIntervalSince(p)) }
        return max(0, stop.timeIntervalSince(start) - paused)
    }

    /// Start shifted by finished pauses: a count-up timer from here, frozen
    /// at `pausedAt` while paused, shows the right elapsed time.
    var timerAnchor: Date { start.addingTimeInterval(pausedTotal ?? 0) }

    static func sleep(start: Date, end: Date? = nil) -> Entry {
        Entry(kind: .sleep, start: start, end: end)
    }

    static func breast(_ side: BreastSide, start: Date, end: Date? = nil) -> Entry {
        Entry(kind: .feed, start: start, end: end, feedMethod: .breast, side: side)
    }

    static func bottle(ml: Double, content: BottleContent?, at date: Date) -> Entry {
        Entry(kind: .feed, start: date, end: date, feedMethod: .bottle, amountML: ml, bottleContent: content)
    }

    static func solids(at date: Date, note: String?) -> Entry {
        Entry(kind: .feed, start: date, end: date, feedMethod: .solids, note: note)
    }
}

enum FeedingStyle: String, Codable, CaseIterable, Sendable {
    case breast, bottle, mixed

    var title: String {
        switch self {
        case .breast: "Breastfeeding"
        case .bottle: "Bottle"
        case .mixed: "Both"
        }
    }
}

enum VolumeUnit: String, Codable, CaseIterable, Sendable {
    case ml, oz

    static let mlPerOz = 29.5735
}

struct BabyProfile: Codable, Equatable, Sendable {
    var name: String
    var birthDate: Date
    /// Set for babies born early: the age used for wake windows is then the
    /// corrected age (counted from the due date) until 2 years.
    var dueDate: Date?
    var feedingStyle: FeedingStyle = .breast
    var volumeUnit: VolumeUnit = .ml
    var defaultBottleML: Double = 120
    var napAlerts: Bool = true
    var napAlertLeadMinutes: Int = 10

    init(name: String, birthDate: Date, dueDate: Date? = nil) {
        self.name = name
        self.birthDate = birthDate
        self.dueDate = dueDate
    }

    /// Tolerant decoding so fields added later never wipe a saved profile.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        birthDate = try c.decode(Date.self, forKey: .birthDate)
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        feedingStyle = try c.decodeIfPresent(FeedingStyle.self, forKey: .feedingStyle) ?? .breast
        volumeUnit = try c.decodeIfPresent(VolumeUnit.self, forKey: .volumeUnit) ?? .ml
        defaultBottleML = try c.decodeIfPresent(Double.self, forKey: .defaultBottleML) ?? 120
        napAlerts = try c.decodeIfPresent(Bool.self, forKey: .napAlerts) ?? true
        napAlertLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .napAlertLeadMinutes) ?? 10
    }

    /// Age in whole days, corrected for prematurity when a due date is set.
    func ageInDays(at date: Date, calendar: Calendar = .current) -> Int {
        let actual = calendar.dateComponents([.day], from: calendar.startOfDay(for: birthDate),
                                             to: calendar.startOfDay(for: date)).day ?? 0
        guard let due = dueDate, due > birthDate, actual < 730 else { return max(0, actual) }
        let corrected = calendar.dateComponents([.day], from: calendar.startOfDay(for: due),
                                                to: calendar.startOfDay(for: date)).day ?? 0
        return max(0, corrected)
    }

    var displayName: String { name.isEmpty ? "Baby" : name }
}

struct LogData: Codable, Equatable, Sendable {
    var profile: BabyProfile?
    var entries: [Entry] = []

    init(profile: BabyProfile? = nil, entries: [Entry] = []) {
        self.profile = profile
        self.entries = entries.sorted { $0.start < $1.start }
    }
}

// MARK: - Queries

extension LogData {
    var activeSleep: Entry? { entries.last { $0.kind == .sleep && $0.isRunning } }
    var activeFeed: Entry? { entries.last { $0.kind == .feed && $0.isRunning } }

    var completedSleeps: [Entry] {
        entries.filter { $0.kind == .sleep && !$0.isRunning }
    }

    var lastCompletedSleep: Entry? {
        completedSleeps.max { ($0.end ?? $0.start) < ($1.end ?? $1.start) }
    }

    var lastFeed: Entry? { entries.last { $0.kind == .feed } }

    var lastBreastSide: BreastSide? {
        entries.last { $0.kind == .feed && $0.feedMethod == .breast }?.side
    }

    /// The side to offer next: the opposite of the last breast used.
    var suggestedSide: BreastSide { lastBreastSide?.opposite ?? .left }

    func entries(overlapping interval: DateInterval, now: Date = Date()) -> [Entry] {
        entries.filter { e in
            let end = e.end ?? now
            return end >= interval.start && e.start <= interval.end
        }
    }

    func entry(id: UUID) -> Entry? { entries.first { $0.id == id } }
}

// MARK: - Mutations (pure; persisted by LogStore)

extension LogData {
    mutating func add(_ entry: Entry) {
        let i = entries.firstIndex { $0.start > entry.start } ?? entries.endIndex
        entries.insert(entry, at: i)
    }

    mutating func update(_ entry: Entry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return add(entry) }
        entries.remove(at: i)
        add(entry)
    }

    mutating func delete(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    @discardableResult
    mutating func startSleep(at date: Date) -> Bool {
        guard activeSleep == nil else { return false }
        add(.sleep(start: date))
        return true
    }

    @discardableResult
    mutating func endSleep(at date: Date) -> Entry? {
        guard let e = activeSleep else { return nil }
        return finish(e, at: date)
    }

    /// Pauses the running timer of `kind`, or resumes it if paused.
    /// Returns true if the timer is now paused, nil if none is running.
    @discardableResult
    mutating func togglePause(_ kind: EntryKind, at date: Date) -> Bool? {
        guard var e = kind == .sleep ? activeSleep : activeFeed else { return nil }
        if let p = e.pausedAt {
            e.pausedTotal = (e.pausedTotal ?? 0) + max(0, date.timeIntervalSince(p))
            e.pausedAt = nil
        } else {
            e.pausedAt = max(date, e.start)
        }
        update(e)
        return e.pausedAt != nil
    }

    /// Ends a timer. Stopping while paused ends it when the pause began,
    /// so a pause that turns into "done" isn't counted.
    private mutating func finish(_ entry: Entry, at date: Date) -> Entry {
        var e = entry
        if let p = e.pausedAt {
            e.end = max(p, e.start)
            e.pausedAt = nil
        } else {
            e.end = max(date, e.start)
        }
        update(e)
        return e
    }

    /// Starts a breastfeeding timer; a running feed is closed first, so
    /// "switch sides" is just starting the other side.
    mutating func startBreast(_ side: BreastSide, at date: Date) {
        stopFeed(at: date)
        add(.breast(side, start: date))
    }

    @discardableResult
    mutating func stopFeed(at date: Date) -> Entry? {
        guard let e = activeFeed else { return nil }
        return finish(e, at: date)
    }
}

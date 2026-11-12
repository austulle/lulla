import AppIntents
import Foundation

// App Intents power Siri, the Shortcuts app, the Action button, Spotlight,
// interactive widget buttons, Control Center / Lock Screen controls and the
// Live Activity buttons. Intents that touch a timer are LiveActivityIntents
// so they always run in the app's process (where Live Activities can be
// started), even when tapped from a widget.

enum SideOption: String, AppEnum {
    case left, right

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Side"
    static let caseDisplayRepresentations: [SideOption: DisplayRepresentation] = [
        .left: "Left", .right: "Right",
    ]

    var side: BreastSide { self == .left ? .left : .right }
}

enum BottleOption: String, AppEnum {
    case formula, breastMilk

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bottle contents"
    static let caseDisplayRepresentations: [BottleOption: DisplayRepresentation] = [
        .formula: "Formula", .breastMilk: "Breast milk",
    ]

    var content: BottleContent { self == .formula ? .formula : .breastMilk }
}

private func babyName() -> String { LogStore.shared.load().profile?.displayName ?? "Baby" }

// MARK: - Sleep

struct StartSleepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Sleep"
    static let description = IntentDescription("Starts the sleep timer.")

    @Parameter(title: "Minutes ago", description: "If the baby fell asleep a little while ago.", default: 0)
    var minutesAgo: Int

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let start = Date().addingTimeInterval(-Double(min(max(minutesAgo, 0), 240)) * 60)
        var started = false
        await LullaActions.perform { started = $0.startSleep(at: start) }
        let name = babyName()
        let message = started ? "Sleep started for \(name)." : "\(name) is already asleep."
        return .result(dialog: "\(message)")
    }
}

struct EndSleepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Sleep"
    static let description = IntentDescription("Stops the sleep timer and shows when the next window is.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var ended: Entry?
        let data = await LullaActions.perform { ended = $0.endSleep(at: Date()) }
        guard let ended else { return .result(dialog: "No sleep is running.") }
        let snap = LullaSnapshot.make(data, now: Date())
        return .result(dialog: "Slept \(Format.duration(ended.duration())). \(snap.napPhrase).")
    }
}

struct ToggleSleepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Sleep"
    static let description = IntentDescription("Starts a sleep, or ends the one running.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let asleep = await LullaActions.toggleSleep()
        let message = asleep ? "Sleep started." : "Sleep ended."
        return .result(dialog: "\(message)")
    }
}

/// Backs the Control Center / Lock Screen sleep toggle.
struct SetSleepIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Sleep"

    @Parameter(title: "Asleep")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        let now = Date()
        await LullaActions.perform { d in
            if value { _ = d.startSleep(at: now) } else { _ = d.endSleep(at: now) }
        }
        return .result()
    }
}

/// Play / pause for the running sleep timer.
struct PauseSleepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Sleep"
    static let description = IntentDescription("Pauses the running sleep timer, or resumes it if paused.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var paused: Bool?
        await LullaActions.perform { paused = $0.togglePause(.sleep, at: Date()) }
        guard let paused else { return .result(dialog: "No sleep is running.") }
        let message = paused ? "Sleep paused." : "Sleep resumed."
        return .result(dialog: "\(message)")
    }
}

// MARK: - Feeding

struct StartBreastfeedingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Breastfeeding"
    static let description = IntentDescription("Starts a feeding timer. Leave the side empty to use the suggested side.")

    @Parameter(title: "Side")
    var side: SideOption?

    init() {}
    init(side: SideOption?) { self.side = side }

    static var parameterSummary: some ParameterSummary {
        Summary("Start breastfeeding on \(\.$side)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var chosen = BreastSide.left
        await LullaActions.perform { d in
            chosen = side?.side ?? d.suggestedSide
            d.startBreast(chosen, at: Date())
        }
        return .result(dialog: "Feeding started on the \(chosen.title.lowercased()) side.")
    }
}

struct StopFeedingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Feeding"
    static let description = IntentDescription("Stops the running feeding timer.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var stopped: Entry?
        let data = await LullaActions.perform { stopped = $0.stopFeed(at: Date()) }
        guard let stopped else { return .result(dialog: "No feed is running.") }
        let unit = data.profile?.volumeUnit ?? .ml
        return .result(dialog: "Logged \(Format.feedLabel(stopped, unit: unit)). Next side: \(data.suggestedSide.title.lowercased()).")
    }
}

/// Play / pause for the running feeding timer.
struct PauseFeedingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Feeding"
    static let description = IntentDescription("Pauses the running feeding timer, or resumes it if paused.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var paused: Bool?
        await LullaActions.perform { paused = $0.togglePause(.feed, at: Date()) }
        guard let paused else { return .result(dialog: "No feed is running.") }
        let message = paused ? "Feeding paused." : "Feeding resumed."
        return .result(dialog: "\(message)")
    }
}

/// Backs the Control Center / Lock Screen feeding toggle.
struct SetFeedingIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Feeding"

    @Parameter(title: "Feeding")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        let running = LogStore.shared.load().activeFeed != nil
        if value != running { await LullaActions.toggleFeed() }
        return .result()
    }
}

/// Widget / control feed button (see `LullaActions.toggleFeed`).
struct ToggleFeedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Feeding"
    static let description = IntentDescription("Stops the running feed, or starts one on the suggested side (or logs your usual bottle).")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await LullaActions.toggleFeed() {
        case .stopped(let e): return .result(dialog: "Feed logged: \(Format.duration(e.duration())).")
        case .startedBreast(let s): return .result(dialog: "Feeding started on the \(s.title.lowercased()) side.")
        case .loggedBottle(let ml):
            let unit = LogStore.shared.load().profile?.volumeUnit ?? .ml
            return .result(dialog: "Logged a \(Format.volume(ml: ml, unit: unit)) bottle.")
        }
    }
}

struct LogBottleIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Bottle"
    static let description = IntentDescription("Logs a bottle feed, in the unit set in Lulla.")

    @Parameter(title: "Amount", description: "In ml or oz, as set in Lulla's settings.")
    var amount: Double

    @Parameter(title: "Contents")
    var contents: BottleOption?

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Log a bottle of \(\.$amount)") { \.$contents }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var unit = VolumeUnit.ml
        await LullaActions.perform { d in
            unit = d.profile?.volumeUnit ?? .ml
            let ml = unit == .oz ? amount * VolumeUnit.mlPerOz : amount
            d.add(.bottle(ml: ml, content: contents?.content, at: Date()))
        }
        let ml = unit == .oz ? amount * VolumeUnit.mlPerOz : amount
        return .result(dialog: "Logged a \(Format.volume(ml: ml, unit: unit)) bottle.")
    }
}

// MARK: - Questions

struct NextNapIntent: AppIntent {
    static let title: LocalizedStringResource = "When Is the Next Nap"
    static let description = IntentDescription("Tells you the next nap or bedtime window, based on age and recent sleep.")

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let snap = LullaSnapshot.make(LogStore.shared.load(), now: Date())
        var phrase = snap.napPhrase
        if let since = snap.awakeSince, !snap.isAsleep {
            phrase += ". Awake for \(Format.duration(Date().timeIntervalSince(since)))"
        }
        return .result(value: phrase, dialog: "\(phrase).")
    }
}

struct LastFeedIntent: AppIntent {
    static let title: LocalizedStringResource = "When Was the Last Feed"
    static let description = IntentDescription("Tells you how long ago the last feed was, and the next side.")

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let snap = LullaSnapshot.make(LogStore.shared.load(), now: Date())
        guard let feed = snap.lastFeed else {
            return .result(value: "No feeds yet", dialog: "No feeds logged yet.")
        }
        var phrase = "Last fed \(snap.lastFeedPhrase): \(Format.feedLabel(feed, unit: snap.volumeUnit))"
        if snap.feedingStyle != .bottle { phrase += ". Next side: \(snap.nextSide.title.lowercased())" }
        return .result(value: phrase, dialog: "\(phrase).")
    }
}

import AppIntents
import SwiftUI
import WidgetKit

// Home Screen (small, medium) and Lock Screen (circular, rectangular,
// inline) widget.

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snap: LullaSnapshot
}

struct LullaProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snap: .sample(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let data = LogStore.shared.load()
        let now = Date()
        let snap = (context.isPreview && data.profile == nil) ? LullaSnapshot.sample(now: now) : LullaSnapshot.make(data, now: now)
        completion(SnapshotEntry(date: now, snap: snap))
    }

    /// Entries every 5 minutes for 3 hours: elapsed times and the gauge stay
    /// fresh without spending reload budget. The app reloads timelines on
    /// every change, so a new log shows up immediately.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let data = LogStore.shared.load()
        let now = Date()
        let entries = (0..<36).map { i -> SnapshotEntry in
            let date = now.addingTimeInterval(Double(i) * 300)
            return SnapshotEntry(date: date, snap: LullaSnapshot.make(data, now: date))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct LullaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LullaWidget", provider: LullaProvider()) { entry in
            LullaWidgetView(entry: entry)
        }
        .configurationDisplayName("Lulla")
        .description("The next nap window, running timers and the last feed.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct LullaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidget(snap: entry.snap)
                .containerBackground(for: .widget) { GradientBackdrop(mood: entry.snap.mood) }
        case .accessoryCircular:
            CircularWidget(snap: entry.snap)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            RectangularWidget(snap: entry.snap)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            InlineWidget(snap: entry.snap)
                .containerBackground(for: .widget) { Color.clear }
        default:
            SmallWidget(snap: entry.snap)
                .containerBackground(for: .widget) { GradientBackdrop(mood: entry.snap.mood) }
        }
    }
}

// MARK: - Shared status text

/// The headline / big value / caption trio every family draws from.
struct WidgetStatus {
    enum Big { case text(String), timer(Date, paused: Date?) }

    let label: String
    let big: Big
    let caption: Text
    let icon: String

    init(_ s: LullaSnapshot) {
        if let start = s.feedStart {
            label = (s.isFeedPaused ? "Feed paused" : "Feeding") + (s.feedSide.map { " · \($0.short)" } ?? "")
            big = .timer(s.feedAnchor ?? start, paused: s.feedPausedAt)
            caption = Text("since \(Format.time(start))")
            icon = "drop.fill"
        } else if let start = s.sleepStart {
            label = s.isSleepPaused ? "Sleep paused" : "Asleep"
            big = .timer(s.sleepAnchor ?? start, paused: s.sleepPausedAt)
            caption = Text(s.sleepPausedAt.map { "paused \(Format.time($0))" } ?? "since \(Format.time(start))")
            icon = "moon.zzz.fill"
        } else if s.isNightWaking {
            label = "Night"
            big = .text("Rest")
            caption = Text("awake \(Format.duration(s.now.timeIntervalSince(s.awakeSince ?? s.now)))")
            icon = "moon.stars"
        } else if let p = s.prediction {
            label = p.title
            icon = p.kind == .bedtime ? "bed.double" : "moon.zzz"
            switch p.phase(at: s.now) {
            case .upcoming:
                big = .text(Format.time(p.windowStart))
                caption = Text("in ") + Text(timerInterval: s.now...p.windowStart, countsDown: true)
            case .open:
                big = .text("Now")
                caption = Text("window until \(Format.time(p.windowEnd))")
            case .late:
                big = .text("Now")
                caption = Text("window passed \(Format.time(p.windowEnd))")
            }
        } else {
            label = "Next nap"
            big = .text("—")
            caption = Text(s.hasProfile ? "log a sleep" : "open Lulla")
            icon = "moon.zzz"
        }
    }

    @ViewBuilder func bigView(size: CGFloat) -> some View {
        switch big {
        case .text(let t): Text(t).font(.lullaSerif(size)).minimumScaleFactor(0.6).lineLimit(1)
        case .timer(let d, let paused): ElapsedText(anchor: d, pausedAt: paused).font(.lullaSerif(size)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Home Screen

struct SmallWidget: View {
    let snap: LullaSnapshot

    var body: some View {
        let st = WidgetStatus(snap)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MonoLabel(snap.babyName, color: snap.mood.onGradient)
                Spacer()
                Image(systemName: st.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(snap.mood.onGradient)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                MonoLabel(st.label)
                st.bigView(size: 32)
                    .foregroundStyle(Color.lullaInk)
                st.caption
                    .font(.lullaMono(10.5))
                    .foregroundStyle(Color.lullaMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.lullaCream)
        }
        .widgetURL(URL(string: "lulla://today"))
    }
}

struct MediumWidget: View {
    let snap: LullaSnapshot

    var body: some View {
        let st = WidgetStatus(snap)
        let ink = snap.mood.onGradient
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: st.icon).font(.system(size: 11))
                    MonoLabel(st.label, color: ink)
                }
                .foregroundStyle(ink)
                st.bigView(size: 38).foregroundStyle(ink).padding(.top, 6)
                st.caption.font(.lullaMono(10.5)).foregroundStyle(ink.opacity(0.8))
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                MonoLabel("Last feed")
                Text(snap.lastFeedPhrase)
                    .font(.lullaSerif(19))
                    .foregroundStyle(Color.lullaInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                MonoLabel(feedDetail, color: .lullaMuted)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if snap.isAsleep {
                        Button(intent: PauseSleepIntent()) {
                            pill(snap.isSleepPaused ? LullaIcon.play : LullaIcon.pause, filled: false)
                        }
                        Button(intent: EndSleepIntent()) { pill(LullaIcon.stop, filled: true) }
                    } else {
                        Button(intent: StartSleepIntent()) { pill(LullaIcon.play, filled: true) }
                        Button(intent: ToggleFeedIntent()) {
                            pill(snap.isFeeding ? LullaIcon.stop : LullaIcon.feed, filled: false)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(width: 150)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Color.lullaCream)
        }
        .widgetURL(URL(string: "lulla://today"))
    }

    private var feedDetail: String {
        if snap.isAsleep { return snap.isSleepPaused ? "Sleep paused" : "Pause · stop sleep" }
        if snap.isFeeding { return "Tap ■ to stop" }
        if snap.feedingStyle == .bottle { return "Tap to log usual" }
        return "Next side · \(snap.nextSide.short)"
    }

    private func pill(_ symbol: String, filled: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(filled ? Color.lullaCream : Color.lullaInk)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(filled ? Color.lullaInk : Color.lullaInk.opacity(0.08), in: Capsule())
    }
}

// MARK: - Lock Screen

struct CircularWidget: View {
    let snap: LullaSnapshot

    var body: some View {
        Group {
            if let start = snap.sleepStart ?? snap.feedStart {
                let feeding = snap.sleepStart == nil
                let paused = feeding ? snap.feedPausedAt : snap.sleepPausedAt
                VStack(spacing: 1) {
                    Image(systemName: paused != nil ? "pause.fill" : (feeding ? "drop.fill" : "moon.zzz.fill")).font(.system(size: 12))
                    ElapsedText(anchor: (feeding ? snap.feedAnchor : snap.sleepAnchor) ?? start, pausedAt: paused)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                }
                .padding(4)
            } else if let p = snap.prediction {
                Gauge(value: progress(p)) {
                    Image(systemName: p.kind == .bedtime ? "bed.double" : "moon.zzz")
                } currentValueLabel: {
                    if p.phase(at: snap.now) == .upcoming {
                        Text(p.windowStart, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    } else {
                        Text("Now").font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                Image(systemName: "moon.zzz").font(.system(size: 20))
            }
        }
        .widgetURL(URL(string: "lulla://today"))
    }

    private func progress(_ p: NapPrediction) -> Double {
        let total = p.windowStart.timeIntervalSince(p.awakeSince)
        guard total > 0 else { return 1 }
        return min(max(snap.now.timeIntervalSince(p.awakeSince) / total, 0), 1)
    }
}

struct RectangularWidget: View {
    let snap: LullaSnapshot

    var body: some View {
        let st = WidgetStatus(snap)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: st.icon)
                Text(st.label.uppercased()).font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .widgetAccentable()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                st.bigView(size: 20).fontWeight(.semibold)
                st.caption.font(.system(size: 12))
            }
            Text("Fed \(snap.lastFeedPhrase.lowercased())" + (snap.feedingStyle == .bottle ? "" : " · \(snap.nextSide.short) next"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "lulla://today"))
    }
}

struct InlineWidget: View {
    let snap: LullaSnapshot

    var body: some View {
        if let start = snap.sleepStart {
            Label {
                Text(snap.isSleepPaused ? "Paused " : "Asleep ")
                    + Text(timerInterval: (snap.sleepAnchor ?? start)...Date.distantFuture, pauseTime: snap.sleepPausedAt, countsDown: false)
            } icon: { Image(systemName: snap.isSleepPaused ? "pause.fill" : "moon.zzz.fill") }
        } else if let p = snap.prediction {
            Label("\(p.title) \(Format.time(p.windowStart)) · fed \(snap.lastFeedPhrase)", systemImage: "moon.zzz")
        } else {
            Label("Fed \(snap.lastFeedPhrase)", systemImage: "drop")
        }
    }
}

// MARK: - Preview data

extension LullaSnapshot {
    /// Gallery preview before any data exists.
    static func sample(now: Date) -> LullaSnapshot {
        var profile = BabyProfile(name: "Mila", birthDate: now.addingTimeInterval(-100 * 86400))
        profile.feedingStyle = .breast
        let data = LogData(profile: profile, entries: [
            .sleep(start: now.addingTimeInterval(-11 * 3600), end: now.addingTimeInterval(-3 * 3600)),
            .sleep(start: now.addingTimeInterval(-110 * 60), end: now.addingTimeInterval(-45 * 60)),
            .breast(.left, start: now.addingTimeInterval(-40 * 60), end: now.addingTimeInterval(-25 * 60)),
        ])
        return .make(data, now: now)
    }
}

import SwiftUI

// MARK: - Buttons

struct InkButtonStyle: ButtonStyle {
    var fill: Color = .lullInk
    var text: Color = .lullCream

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.lullInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(Capsule().stroke(Color.lullInk.opacity(0.35), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Hero

struct HeroCard: View {
    @Environment(LogModel.self) private var model
    @Environment(Router.self) private var router
    let snap: LullSnapshot

    var body: some View {
        CreamPanel(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                if let start = snap.sleepStart {
                    asleep(since: start)
                } else if snap.isNightWaking {
                    nightWaking
                } else if let p = snap.prediction {
                    window(p)
                } else {
                    empty
                }
            }
        }
    }

    private func asleep(since start: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                MonoLabel("Asleep · since \(Format.time(start))")
                Spacer()
                OrbitMark().frame(width: 64, height: 44)
            }
            Text(start, style: .timer)
                .font(.lullSerif(58))
                .monospacedDigit()
                .foregroundStyle(Color.lullInk)
            DashedRule()
            Button {
                model.mutate { $0.endSleep(at: Date()) }
            } label: {
                Label("Wake up", systemImage: LullIcon.wake)
            }
            .buttonStyle(InkButtonStyle())
            .sensoryFeedback(.success, trigger: snap.sleepStart)
        }
    }

    private func window(_ p: NapPrediction) -> some View {
        let phase = p.phase(at: snap.now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                MonoLabel(p.kind == .bedtime ? "Bedtime window" : "Nap \(p.napNumber) window")
                Spacer()
                MonoLabel(phaseTag(phase), color: phase == .late ? Color(hex: 0xB4442E) : .lullInk.opacity(0.7))
            }
            Text("\(Format.time(p.windowStart))–\(Format.time(p.windowEnd))")
                .font(.lullSerif(46))
                .foregroundStyle(Color.lullInk)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Group {
                switch phase {
                case .upcoming:
                    Text("Opens in \(Format.duration(p.windowStart.timeIntervalSince(snap.now))) · aim for \(Format.time(p.target))")
                case .open:
                    Text("The window is open — wind down now.")
                case .late:
                    Text("\(Format.duration(snap.now.timeIntervalSince(p.windowEnd))) past the window. Try now; a shorter nap is fine.")
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Color.lullInk.opacity(0.8))

            WakeBar(prediction: p, now: snap.now)
                .frame(height: 22)

            DashedRule()
            HStack(spacing: 14) {
                stat("Awake", Format.duration(snap.now.timeIntervalSince(p.awakeSince)))
                stat("Typical", "\(Format.minutes(p.typicalMinutes.lowerBound))–\(Format.minutes(p.typicalMinutes.upperBound))")
                stat("Using", Format.minutes(p.targetMinutes))
            }
            if p.personalized || p.shortNapAdjusted {
                HStack(spacing: 6) {
                    if p.personalized { Tag("Tuned to \(snap.babyName)'s week") }
                    if p.shortNapAdjusted { Tag("Short nap · shorter window") }
                }
            }
            Button {
                model.mutate { $0.startSleep(at: Date()) }
            } label: {
                Label("Start sleep", systemImage: LullIcon.sleep)
            }
            .buttonStyle(InkButtonStyle())
            .sensoryFeedback(.impact, trigger: snap.sleepStart)
        }
    }

    private var nightWaking: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                MonoLabel("Night")
                Spacer()
                OrbitMark().frame(width: 64, height: 44)
            }
            Text("Night waking")
                .font(.lullSerif(42))
                .foregroundStyle(Color.lullInk)
            if let since = snap.awakeSince {
                Text("Awake \(Format.duration(snap.now.timeIntervalSince(since))). Keep it dim and calm.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.lullInk.opacity(0.8))
            }
            Button {
                model.mutate { $0.startSleep(at: Date()) }
            } label: {
                Label("Back to sleep", systemImage: LullIcon.sleep)
            }
            .buttonStyle(InkButtonStyle())
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel("Next window")
            Text("Start with a sleep.")
                .font(.lullSerif(40))
                .foregroundStyle(Color.lullInk)
            Text("Log the last sleep and Lull shows when the next nap window opens, based on \(snap.babyName)'s age and recent days.")
                .font(.system(size: 15))
                .foregroundStyle(Color.lullInk.opacity(0.8))
            HStack(spacing: 10) {
                Button("Asleep now") { model.mutate { $0.startSleep(at: Date()) } }
                    .buttonStyle(InkButtonStyle())
                Button("Add past sleep") { router.sheet = .add(.sleep) }
                    .buttonStyle(OutlineButtonStyle())
            }
        }
    }

    private func phaseTag(_ phase: NapPrediction.Phase) -> String {
        switch phase {
        case .upcoming: "Upcoming"
        case .open: "Open now"
        case .late: "Late"
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            MonoLabel(label, color: .lullMuted)
            Text(value).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.lullInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.lullMono(9.5))
            .tracking(0.8)
            .foregroundStyle(Color.lullForest)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: 0xC8E85A).opacity(0.55), in: Capsule())
    }
}

/// Awake time so far against the window: a hairline track, a filled
/// "awake" portion and the window as a gradient segment.
struct WakeBar: View {
    let prediction: NapPrediction
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let start = prediction.awakeSince
            let end = max(prediction.windowEnd.addingTimeInterval(20 * 60), now)
            let span = max(end.timeIntervalSince(start), 1)
            let x: (Date) -> CGFloat = { CGFloat($0.timeIntervalSince(start) / span) * geo.size.width }
            let mid = geo.size.height / 2

            ZStack(alignment: .leading) {
                DashedRule().offset(y: 0)
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xC8E85A), Color(hex: 0x3FAF7A)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(x(prediction.windowEnd) - x(prediction.windowStart), 6), height: 10)
                    .offset(x: x(prediction.windowStart))
                Capsule()
                    .fill(Color.lullInk)
                    .frame(width: max(x(min(now, end)), 2), height: 2)
                Circle()
                    .fill(Color.lullInk)
                    .frame(width: 9, height: 9)
                    .offset(x: x(min(now, end)) - 4.5)
            }
            .frame(height: geo.size.height)
            .position(x: geo.size.width / 2, y: mid)
        }
    }
}

// MARK: - Feed timer

struct FeedTimerCard: View {
    @Environment(LogModel.self) private var model
    let snap: LullSnapshot

    var body: some View {
        CreamPanel {
            VStack(alignment: .leading, spacing: 12) {
                MonoLabel("Feeding" + (snap.feedSide.map { " · \($0.title)" } ?? ""))
                if let start = snap.feedStart {
                    Text(start, style: .timer)
                        .font(.lullSerif(44))
                        .monospacedDigit()
                        .foregroundStyle(Color.lullInk)
                }
                HStack(spacing: 10) {
                    if let side = snap.feedSide {
                        Button("Switch to \(side.opposite.short)") {
                            model.mutate { $0.startBreast(side.opposite, at: Date()) }
                        }
                        .buttonStyle(OutlineButtonStyle())
                    }
                    Button("Done") { model.mutate { $0.stopFeed(at: Date()) } }
                        .buttonStyle(InkButtonStyle())
                }
            }
        }
    }
}

// MARK: - Quick actions

struct ActionRow: View {
    @Environment(LogModel.self) private var model
    @Environment(Router.self) private var router
    let snap: LullSnapshot

    var body: some View {
        HStack(spacing: 10) {
            tile(snap.isAsleep ? "Wake" : "Sleep",
                 icon: snap.isAsleep ? LullIcon.wake : LullIcon.sleep) {
                model.mutate { d in
                    if d.activeSleep != nil { _ = d.endSleep(at: Date()) } else { _ = d.startSleep(at: Date()) }
                }
            }
            tile(snap.isFeeding ? "Stop feed" : "Feed",
                 icon: snap.isFeeding ? "stop.circle" : LullIcon.feed,
                 detail: snap.isFeeding || snap.feedingStyle == .bottle ? nil : "Next \(snap.nextSide.short)") {
                if snap.isFeeding { model.mutate { _ = $0.stopFeed(at: Date()) } } else { router.sheet = .feed }
            }
            tile("Diaper", icon: LullIcon.diaper) { router.sheet = .diaper }
        }
    }

    private func tile(_ title: String, icon: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: icon).font(.system(size: 20, weight: .light))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium))
                    MonoLabel(detail ?? " ", color: .lullMuted)
                }
            }
            .foregroundStyle(Color.lullInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.lullCream.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: snap.isAsleep)
    }
}

// MARK: - Timeline strip

/// The last 18 hours and the next 6: sleep blocks, feeds, diapers, the
/// predicted window and a "now" line.
struct DayStrip: View {
    let data: LogData
    let snap: LullSnapshot

    var body: some View {
        let start = snap.now.addingTimeInterval(-18 * 3600)
        let end = snap.now.addingTimeInterval(6 * 3600)
        let entries = data.entries(overlapping: DateInterval(start: start, end: end), now: snap.now)

        CreamPanel(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MonoLabel("Last 18 h")
                    Spacer()
                    MonoLabel("Next 6 h", color: .lullMuted)
                }
                Canvas { ctx, size in
                    let span = end.timeIntervalSince(start)
                    func x(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(start) / span) * size.width }
                    let trackY: CGFloat = 16, trackH: CGFloat = 26

                    // Hour grid + labels every 3 h.
                    let cal = Calendar.current
                    var tick = cal.nextDate(after: start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? start
                    while tick < end {
                        let h = cal.component(.hour, from: tick)
                        if h % 3 == 0 {
                            var p = Path()
                            p.move(to: CGPoint(x: x(tick), y: trackY - 4))
                            p.addLine(to: CGPoint(x: x(tick), y: trackY + trackH + 4))
                            ctx.stroke(p, with: .color(.lullInk.opacity(0.12)), lineWidth: 0.5)
                            ctx.draw(Text(String(format: "%02d", h)).font(.lullMono(8.5)).foregroundStyle(Color.lullMuted),
                                     at: CGPoint(x: x(tick), y: trackY + trackH + 13))
                        }
                        tick = tick.addingTimeInterval(3600)
                    }

                    // Predicted window.
                    if let p = snap.prediction {
                        let r = CGRect(x: x(p.windowStart), y: trackY, width: max(x(p.windowEnd) - x(p.windowStart), 4), height: trackH)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 5), with: .color(Color(hex: 0xC8E85A).opacity(0.7)))
                        ctx.stroke(Path(roundedRect: r, cornerRadius: 5), with: .color(.lullForest.opacity(0.6)),
                                   style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                    }

                    // Sleep blocks.
                    for e in entries where e.kind == .sleep {
                        let s = max(e.start, start), t = min(e.end ?? snap.now, end)
                        guard t > s else { continue }
                        let r = CGRect(x: x(s), y: trackY, width: max(x(t) - x(s), 2), height: trackH)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 5),
                                 with: .linearGradient(Gradient(colors: [Color(hex: 0x7C8FEA), Color(hex: 0x3A5BD9)]),
                                                       startPoint: CGPoint(x: r.minX, y: r.minY),
                                                       endPoint: CGPoint(x: r.minX, y: r.maxY)))
                    }

                    // Feeds above, diapers below.
                    for e in entries where e.kind == .feed {
                        let cx = x(e.start)
                        ctx.fill(Path(ellipseIn: CGRect(x: cx - 3.5, y: 2, width: 7, height: 7)), with: .color(Color(hex: 0xEE9DB8)))
                    }
                    for e in entries where e.kind == .diaper {
                        let cx = x(e.start)
                        ctx.fill(Path(CGRect(x: cx - 0.75, y: trackY + trackH - 7, width: 1.5, height: 7)), with: .color(.lullForest))
                    }

                    // Now.
                    var now = Path()
                    now.move(to: CGPoint(x: x(snap.now), y: 0))
                    now.addLine(to: CGPoint(x: x(snap.now), y: trackY + trackH + 4))
                    ctx.stroke(now, with: .color(.lullInk), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
                .frame(height: 62)

                HStack(spacing: 14) {
                    legend(Color(hex: 0x3A5BD9), "Sleep")
                    legend(Color(hex: 0xEE9DB8), "Feed")
                    legend(Color(hex: 0xC8E85A), "Window")
                }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            MonoLabel(text, color: .lullMuted)
        }
    }
}

// MARK: - Summary

struct SummaryCard: View {
    let snap: LullSnapshot

    var body: some View {
        CreamPanel(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                MonoLabel("Today")
                HStack(alignment: .firstTextBaseline) {
                    stat("Sleep", Format.duration(snap.todaySleep))
                    stat("Naps", "\(snap.todayNaps)")
                    stat("Feeds", "\(snap.todayFeeds)")
                    stat("Diapers", "\(snap.todayDiapers)")
                }
                DashedRule()
                HStack {
                    MonoLabel("Last feed", color: .lullMuted)
                    Spacer()
                    Text(snap.lastFeed.map { "\(snap.lastFeedPhrase) · \(Format.feedLabel($0, unit: snap.volumeUnit, now: snap.now))" } ?? "—")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.lullInk)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.lullSerif(24)).foregroundStyle(Color.lullInk).lineLimit(1).minimumScaleFactor(0.7)
            MonoLabel(label, color: .lullMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Recent

struct RecentCard: View {
    @Environment(Router.self) private var router
    @Environment(LogModel.self) private var model
    let data: LogData
    let snap: LullSnapshot

    var body: some View {
        let recent = Array(data.entries
            .filter { $0.start > snap.now.addingTimeInterval(-24 * 3600) }
            .reversed()
            .prefix(14))

        CreamPanel(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MonoLabel("Last 24 h")
                    Spacer()
                    Menu {
                        Button("Sleep", systemImage: LullIcon.sleep) { router.sheet = .add(.sleep) }
                        Button("Feed", systemImage: LullIcon.feed) { router.sheet = .add(.feed) }
                        Button("Diaper", systemImage: LullIcon.diaper) { router.sheet = .add(.diaper) }
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.lullMono(11))
                            .foregroundStyle(Color.lullInk)
                    }
                }
                .padding(.bottom, 8)

                if recent.isEmpty {
                    Text("Nothing logged in the last day.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.lullMuted)
                        .padding(.vertical, 10)
                }
                ForEach(recent) { e in
                    Button { router.sheet = .edit(e) } label: {
                        EntryRow(entry: e, unit: snap.volumeUnit, now: snap.now)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            model.mutate { $0.delete(id: e.id) }
                        }
                    }
                    if e.id != recent.last?.id { DashedRule() }
                }
            }
        }
    }
}

struct EntryRow: View {
    let entry: Entry
    let unit: VolumeUnit
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: LullIcon.symbol(for: entry))
                .font(.system(size: 14, weight: .light))
                .frame(width: 30, height: 30)
                .background(Circle().stroke(Color.lullInk.opacity(0.2), lineWidth: 0.75))
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.title(entry, unit: unit, now: now))
                    .font(.system(size: 15))
                if entry.isRunning {
                    MonoLabel("Running", color: Color(hex: 0x1F8A5B))
                } else if let note = entry.note, !note.isEmpty {
                    Text(note).font(.system(size: 12)).foregroundStyle(Color.lullMuted).lineLimit(1)
                }
            }
            Spacer()
            Text(timeText)
                .font(.lullMono(11))
                .foregroundStyle(Color.lullMuted)
        }
        .foregroundStyle(Color.lullInk)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var timeText: String {
        if let end = entry.end, end != entry.start {
            return "\(Format.time(entry.start))–\(Format.time(end))"
        }
        return Format.time(entry.start)
    }
}

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct LullaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LullaActivityAttributes.self) { context in
            LockScreenActivity(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.clear)
                .activitySystemActionForegroundColor(.lullaInk)
                .widgetURL(URL(string: "lulla://today"))
        } dynamicIsland: { context in
            let isSleep = context.attributes.kind == .sleep
            let icon = context.state.isPaused ? "pause.fill" : (isSleep ? "moon.zzz.fill" : "drop.fill")
            let accent = isSleep ? Color(hex: 0x9AA8F2) : Color(hex: 0xF4A6BF)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(isSleep ? (context.state.isPaused ? "Paused" : "Asleep") : feedTitle(context.state), systemImage: icon)
                        .font(.lullaMono(12))
                        .foregroundStyle(accent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(anchor: context.state.anchor, pausedAt: context.state.pausedAt)
                        .font(.lullaSerif(28))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("\(context.attributes.babyName) · since \(Format.time(context.state.start))")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                        ActivityButtons(kind: context.attributes.kind, state: context.state, dark: true)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: icon).foregroundStyle(accent)
            } compactTrailing: {
                ElapsedText(anchor: context.state.anchor, pausedAt: context.state.pausedAt)
                    .frame(maxWidth: 56)
                    .foregroundStyle(accent)
            } minimal: {
                Image(systemName: icon).foregroundStyle(accent)
            }
            .keylineTint(accent)
            .widgetURL(URL(string: "lulla://today"))
        }
    }

    private func feedTitle(_ s: LullaActivityAttributes.ContentState) -> String {
        (s.isPaused ? "Paused" : "Feeding") + (s.side.map { " · \($0.short)" } ?? "")
    }
}

private struct LockScreenActivity: View {
    let attributes: LullaActivityAttributes
    let state: LullaActivityAttributes.ContentState

    var body: some View {
        let isSleep = attributes.kind == .sleep
        let mood: LullaSnapshot.Mood = isSleep ? (LullaSnapshot.isNightHour(state.start) ? .night : .asleep) : .feeding
        let ink = mood.onGradient

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel(isSleep
                          ? "\(attributes.babyName) · " + (state.isPaused ? "sleep paused" : "asleep")
                          : "\(attributes.babyName) · " + (state.isPaused ? "feed paused" : "feeding") + (state.side.map { " · \($0.title)" } ?? ""),
                          color: ink.opacity(0.85))
                ElapsedText(anchor: state.anchor, pausedAt: state.pausedAt)
                    .font(.lullaSerif(40))
                    .foregroundStyle(ink)
                MonoLabel(state.pausedAt.map { "paused \(Format.time($0))" } ?? "since \(Format.time(state.start))", color: ink.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ActivityButtons(kind: attributes.kind, state: state, dark: false)
        }
        .padding(18)
        .background(GradientBackdrop(mood: mood))
    }
}

private struct ActivityButtons: View {
    let kind: LullaActivityAttributes.Kind
    let state: LullaActivityAttributes.ContentState
    let dark: Bool

    var body: some View {
        HStack(spacing: 6) {
            if kind == .sleep {
                Button(intent: PauseSleepIntent()) { round(state.isPaused ? LullaIcon.play : LullaIcon.pause) }
                Button(intent: EndSleepIntent()) { round(LullaIcon.stop, primary: true) }
            } else {
                Button(intent: PauseFeedingIntent()) { round(state.isPaused ? LullaIcon.play : LullaIcon.pause) }
                if let side = state.side {
                    Button(intent: StartBreastfeedingIntent(side: side.opposite == .left ? .left : .right)) {
                        pill("→ \(side.opposite.short)", primary: false)
                    }
                }
                Button(intent: StopFeedingIntent()) { round(LullaIcon.stop, primary: true) }
            }
        }
        .buttonStyle(.plain)
    }

    private func round(_ symbol: String, primary: Bool = false) -> some View {
        let fill: Color = primary ? (dark ? .white : .lullaCream) : (dark ? .white.opacity(0.18) : .lullaCream.opacity(0.55))
        return Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(primary || !dark ? Color.lullaInk : .white)
            .frame(width: 40, height: 40)
            .background(fill, in: Circle())
    }

    private func pill(_ text: String, primary: Bool) -> some View {
        let fill: Color = primary ? (dark ? .white : .lullaCream) : (dark ? .white.opacity(0.18) : .lullaCream.opacity(0.55))
        return Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(primary || !dark ? Color.lullaInk : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(fill, in: Capsule())
    }
}

import SwiftUI
import WidgetKit

@main
struct LullWidgetBundle: WidgetBundle {
    var body: some Widget {
        LullWidget()
        LullLiveActivity()
        SleepControl()
        FeedControl()
    }
}

// MARK: - Controls (Control Center, Lock Screen corners, Action button)

struct SleepControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.lull.baby.control.sleep", provider: Provider()) { asleep in
            ControlWidgetToggle("Sleep", isOn: asleep, action: SetSleepIntent()) { on in
                Label(on ? "Asleep" : "Awake", systemImage: on ? "moon.zzz.fill" : "moon.zzz")
            }
            .tint(Color(hex: 0x7C8FEA))
        }
        .displayName("Sleep timer")
        .description("Start or end a sleep.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { LogStore.shared.load().activeSleep != nil }
    }
}

struct FeedControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.lull.baby.control.feed", provider: Provider()) { feeding in
            ControlWidgetToggle("Feed", isOn: feeding, action: SetFeedingIntent()) { on in
                Label(on ? "Feeding" : "Feed", systemImage: on ? "drop.fill" : "drop")
            }
            .tint(Color(hex: 0xEE9DB8))
        }
        .displayName("Feeding timer")
        .description("Starts a feed on the next side (or logs your usual bottle), or stops the running feed.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { LogStore.shared.load().activeFeed != nil }
    }
}

import Foundation
import UserNotifications
import WidgetKit

/// The single write path used by the app, widgets, controls and Siri:
/// mutate the shared log, then refresh every surface that shows it.
enum LullActions {
    @discardableResult
    static func perform(_ body: (inout LogData) -> Void) async -> LogData {
        let data = LogStore.shared.update(body)
        await refreshSurfaces(data)
        return data
    }

    static func refreshSurfaces(_ data: LogData) async {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        await LiveActivitySync.sync(data)
        await NapAlerts.reschedule(data)
        ChangeSignal.post()
    }

    // MARK: - Common actions

    /// Starts a sleep, or ends the running one. Returns true if now asleep.
    @discardableResult
    static func toggleSleep(at date: Date = Date()) async -> Bool {
        var asleep = false
        await perform { d in
            if d.activeSleep != nil { _ = d.endSleep(at: date) } else { _ = d.startSleep(at: date); asleep = true }
        }
        return asleep
    }

    /// Feed button on widgets/controls: stops a running feed; otherwise
    /// starts the suggested breast (breastfeeding) or logs the default
    /// bottle (bottle feeding).
    enum FeedToggleResult { case stopped(Entry), startedBreast(BreastSide), loggedBottle(Double) }

    @discardableResult
    static func toggleFeed(at date: Date = Date()) async -> FeedToggleResult {
        var result = FeedToggleResult.startedBreast(.left)
        await perform { d in
            if let stopped = d.stopFeed(at: date) {
                result = .stopped(stopped)
            } else if d.profile?.feedingStyle == .bottle {
                let ml = d.profile?.defaultBottleML ?? 120
                d.add(.bottle(ml: ml, content: nil, at: date))
                result = .loggedBottle(ml)
            } else {
                let side = d.suggestedSide
                d.startBreast(side, at: date)
                result = .startedBreast(side)
            }
        }
        return result
    }
}

/// Cross-process "the log changed" ping so the running app reloads when a
/// widget button or Siri wrote to the shared file.
enum ChangeSignal {
    static let name = "com.lull.baby.log-changed" as CFString

    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name), nil, nil, true)
    }
}

/// Local notification when the next nap window is about to open.
enum NapAlerts {
    static let id = "lull.nap-window"

    static func reschedule(_ data: LogData, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let profile = data.profile, profile.napAlerts,
              let p = NapPredictor().predict(data, now: now) else { return }
        let fireAt = p.windowStart.addingTimeInterval(-Double(profile.napAlertLeadMinutes) * 60)
        guard fireAt > now.addingTimeInterval(30) else { return }

        let content = UNMutableNotificationContent()
        content.title = p.kind == .bedtime ? "Bedtime window soon" : "Nap window soon"
        content.body = "\(profile.displayName)'s \(p.title.lowercased()) window opens at \(Format.time(p.windowStart)) "
            + "(awake \(Format.duration(p.windowStart.timeIntervalSince(p.awakeSince))) by then)."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireAt.timeIntervalSince(now), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}

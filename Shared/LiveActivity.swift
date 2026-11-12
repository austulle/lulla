import ActivityKit
import Foundation

/// A running sleep or feeding timer on the Lock Screen and Dynamic Island.
struct LullaActivityAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable { case sleep, feed }

    struct ContentState: Codable, Hashable {
        var start: Date
        var side: BreastSide?
    }

    var kind: Kind
    var babyName: String
}

/// Keeps Live Activities in step with the log: one per running timer kind.
/// Activities can only be started from the app process — every intent that
/// changes a timer is a `LiveActivityIntent`, which runs there.
enum LiveActivitySync {
    static func sync(_ data: LogData) async {
        let name = data.profile?.displayName ?? "Baby"
        for kind in [LullaActivityAttributes.Kind.sleep, .feed] {
            let running = kind == .sleep ? data.activeSleep : data.activeFeed
            let existing = Activity<LullaActivityAttributes>.activities.filter { $0.attributes.kind == kind }

            guard let running else {
                for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
                continue
            }

            let state = LullaActivityAttributes.ContentState(start: running.start, side: running.side)
            if let current = existing.first {
                if current.content.state != state {
                    await current.update(ActivityContent(state: state, staleDate: nil))
                }
                for extra in existing.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                _ = try? Activity.request(
                    attributes: LullaActivityAttributes(kind: kind, babyName: name),
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            }
        }
    }
}

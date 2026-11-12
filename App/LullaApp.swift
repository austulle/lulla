import SwiftUI

@main
struct LullaApp: App {
    @State private var model = LogModel()
    @State private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(router)
                .onOpenURL { router.handle($0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.reloadAndRefresh() }
                }
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(LogModel.self) private var model

    var body: some View {
        if model.data.profile == nil {
            OnboardingView()
        } else {
            TodayView()
        }
    }
}

/// App-side owner of the log. Writes go through `LogStore` synchronously
/// (instant UI) and then refresh widgets, Live Activities and alerts.
@MainActor @Observable
final class LogModel {
    private(set) var data: LogData

    init() {
        data = LogStore.shared.load()
        observeExternalChanges()
    }

    func reload() {
        let fresh = LogStore.shared.load()
        if fresh != data { data = fresh }
    }

    /// On foreground: pick up widget/Siri writes and resync surfaces (e.g. a
    /// Live Activity the system ended after 8 hours).
    func reloadAndRefresh() {
        reload()
        let snapshot = data
        Task { await LullaActions.refreshSurfaces(snapshot) }
    }

    func mutate(_ body: (inout LogData) -> Void) {
        data = LogStore.shared.update(body)
        let snapshot = data
        Task { await LullaActions.refreshSurfaces(snapshot) }
    }

    var snapshotNow: LullaSnapshot { LullaSnapshot.make(data, now: Date()) }

    private func observeExternalChanges() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let model = Unmanaged<LogModel>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in model.reload() }
            },
            ChangeSignal.name, nil, .deliverImmediately)
    }
}

/// Sheets and deep links (lulla://feed, lulla://history).
@MainActor @Observable
final class Router {
    enum Sheet: Identifiable, Equatable {
        case feed, history, settings
        case edit(Entry)
        case add(EntryKind)

        var id: String {
            switch self {
            case .feed: "feed"
            case .history: "history"
            case .settings: "settings"
            case .edit(let e): "edit-\(e.id)"
            case .add(let k): "add-\(k.rawValue)"
            }
        }
    }

    var sheet: Sheet?

    func handle(_ url: URL) {
        guard url.scheme == "lulla" else { return }
        switch url.host() {
        case "feed": sheet = .feed
        case "history": sheet = .history
        default: sheet = nil
        }
    }
}

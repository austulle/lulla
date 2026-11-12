import SwiftUI

struct TodayView: View {
    @Environment(LogModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        let data = model.data // read outside the TimelineView so Observation tracks it

        TimelineView(.everyMinute) { context in
            let snap = LullaSnapshot.make(data, now: context.date)
            ZStack {
                GradientBackdrop(mood: snap.mood).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TopBar(snap: snap)
                        HeroCard(snap: snap)
                        if snap.isFeeding { FeedTimerCard(snap: snap) }
                        ActionRow(snap: snap)
                        DayStrip(data: data, snap: snap)
                        SummaryCard(snap: snap)
                        RecentCard(data: data, snap: snap)
                        Text("Nap windows are age-based estimates, not medical advice.")
                            .font(.lullaMono(9.5))
                            .foregroundStyle(snap.mood.onGradient.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(item: $router.sheet) { SheetHost(sheet: $0) }
    }
}

struct SheetHost: View {
    let sheet: Router.Sheet

    var body: some View {
        switch sheet {
        case .feed: FeedSheet()
        case .diaper: DiaperSheet()
        case .history: HistoryView()
        case .settings: SettingsView()
        case .edit(let e): EntryEditor(entry: e, isNew: false)
        case .add(let kind): EntryEditor(entry: EntryEditor.blank(kind), isNew: true)
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @Environment(Router.self) private var router
    let snap: LullaSnapshot

    var body: some View {
        let ink = snap.mood.onGradient
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                MonoLabel("Lulla", color: ink)
                Spacer()
                MonoLabel(snap.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), color: ink.opacity(0.75))
                Button { router.sheet = .history } label: {
                    Image(systemName: "calendar").font(.system(size: 15))
                }
                .padding(.leading, 10)
                Button { router.sheet = .settings } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 15))
                }
                .padding(.leading, 6)
            }
            .foregroundStyle(ink)
            .tint(ink)

            HStack(alignment: .firstTextBaseline) {
                Text(snap.babyName)
                    .font(.lullaSerif(40))
                    .foregroundStyle(ink)
                Spacer()
                MonoLabel(snap.ageText, color: ink.opacity(0.8))
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

import SwiftUI

struct HistoryView: View {
    @Environment(LogModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Entry?

    private struct Day: Identifiable {
        let start: Date
        let entries: [Entry]
        var id: Date { start }
    }

    var body: some View {
        let data = model.data
        let unit = data.profile?.volumeUnit ?? .ml
        let days = Self.days(data)

        NavigationStack {
            List {
                if days.isEmpty {
                    Text("Nothing logged yet.").foregroundStyle(Color.lullaMuted)
                }
                ForEach(days) { day in
                    Section {
                        ForEach(day.entries.reversed()) { e in
                            Button { editing = e } label: { EntryRow(entry: e, unit: unit, now: Date()) }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("Delete", role: .destructive) { model.mutate { $0.delete(id: e.id) } }
                                }
                        }
                    } header: {
                        header(day, data: data, unit: unit)
                    }
                    .listRowBackground(Color.white.opacity(0.55))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.lullaCream)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { EntryEditor(entry: $0, isNew: false) }
        }
        .tint(.lullaInk)
    }

    private func header(_ day: Day, data: LogData, unit: VolumeUnit) -> some View {
        let t = Self.totals(day.start, data: data)
        var parts = ["Sleep \(Format.duration(t.sleep))", "\(t.naps) naps", "\(t.feeds) feeds"]
        if t.bottleML > 0 { parts.append(Format.volume(ml: t.bottleML, unit: unit)) }
        parts.append("\(t.diapers) diapers")
        return VStack(alignment: .leading, spacing: 4) {
            Text(day.start.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.lullaSerif(20))
                .foregroundStyle(Color.lullaInk)
                .textCase(nil)
            Text(parts.joined(separator: " · ").uppercased())
                .font(.lullaMono(9.5))
                .foregroundStyle(Color.lullaMuted)
        }
        .padding(.vertical, 4)
    }

    private static func days(_ data: LogData, limit: Int = 60) -> [Day] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: data.entries) { cal.startOfDay(for: $0.start) }
        return grouped.keys.sorted(by: >).prefix(limit).map { Day(start: $0, entries: grouped[$0] ?? []) }
    }

    private static func totals(_ dayStart: Date, data: LogData) -> (sleep: TimeInterval, naps: Int, feeds: Int, bottleML: Double, diapers: Int) {
        let cal = Calendar.current
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let now = Date()
        let interval = DateInterval(start: dayStart, end: min(dayEnd, max(now, dayStart)))
        let all = data.entries(overlapping: interval, now: now)
        let sleep = all.filter { $0.kind == .sleep }.reduce(0.0) { sum, e in
            sum + max(0, min(e.end ?? now, dayEnd).timeIntervalSince(max(e.start, dayStart)))
        }
        let predictor = NapPredictor()
        let inDay = all.filter { $0.start >= dayStart && $0.start < dayEnd }
        return (
            sleep,
            inDay.filter { $0.kind == .sleep && !predictor.isNightSleep($0) }.count,
            inDay.filter { $0.kind == .feed }.count,
            inDay.filter { $0.feedMethod == .bottle }.compactMap(\.amountML).reduce(0, +),
            inDay.filter { $0.kind == .diaper }.count
        )
    }
}

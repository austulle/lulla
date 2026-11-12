import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(LogModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var profile = BabyProfile(name: "", birthDate: Date())
    @State private var bornEarly = false
    @State private var loaded = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Baby") {
                    TextField("Name", text: $profile.name)
                    DatePicker("Born", selection: $profile.birthDate, in: ...Date(), displayedComponents: .date)
                    Toggle("Born early", isOn: $bornEarly)
                    if bornEarly {
                        DatePicker("Due date", selection: Binding(
                            get: { profile.dueDate ?? profile.birthDate.addingTimeInterval(28 * 86400) },
                            set: { profile.dueDate = $0 }
                        ), in: profile.birthDate..., displayedComponents: .date)
                        Text("Wake windows use the corrected age (from the due date) until 2 years.")
                            .font(.footnote).foregroundStyle(Color.lullaMuted)
                    }
                }

                Section("Feeding") {
                    Picker("Mostly", selection: $profile.feedingStyle) {
                        ForEach(FeedingStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Units", selection: $profile.volumeUnit) {
                        Text("ml").tag(VolumeUnit.ml)
                        Text("oz").tag(VolumeUnit.oz)
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $profile.defaultBottleML, in: 10...400, step: profile.volumeUnit == .ml ? 10 : VolumeUnit.mlPerOz / 2) {
                        Text("Usual bottle  \(Format.volume(ml: profile.defaultBottleML, unit: profile.volumeUnit))")
                    }
                    Text("The widget and Control Center feed button logs the usual bottle when you mostly bottle-feed, and starts a timer on the next side otherwise.")
                        .font(.footnote).foregroundStyle(Color.lullaMuted)
                }

                Section("Nap alerts") {
                    Toggle("Notify before the window opens", isOn: $profile.napAlerts)
                    if profile.napAlerts {
                        Stepper("\(profile.napAlertLeadMinutes) min before", value: $profile.napAlertLeadMinutes, in: 0...30, step: 5)
                    }
                }

                Section("Wake windows at this age") {
                    let band = WakeWindows.band(forAgeDays: profile.ageInDays(at: Date()))
                    row("Age band", band.label)
                    row("Typical naps", "\(band.naps)")
                    row("First window", range(band.first))
                    row("Before bedtime", range(band.last))
                    Text("Lulla starts from these typical ranges, then leans up to halfway toward what has worked for \(profile.displayName) over the last 7 days (windows followed by a nap of 40+ minutes). After a short nap, the next window is shortened by 15%. These are estimates, not medical advice — follow your baby's sleepy cues and your pediatrician.")
                        .font(.footnote).foregroundStyle(Color.lullaMuted)
                }

                Section("Widgets, Siri & controls") {
                    help("Home Screen", "Long-press the Home Screen → Edit → Add Widget → Lulla. The medium size has sleep and feed buttons.")
                    help("Lock Screen", "Long-press the Lock Screen → Customize → add Lulla to the widget row, and Lulla's Sleep or Feed control to the bottom corners.")
                    help("Siri & Shortcuts", "Say “Start sleep in Lulla”, “Next nap in Lulla” or “Log a bottle in Lulla”. All actions are in the Shortcuts app and can go on the Action button.")
                    help("Live Activity", "Running sleep and feeding timers appear on the Lock Screen and in the Dynamic Island.")
                }

                Section("Data") {
                    ShareLink(item: CSVExport(data: model.data),
                              preview: SharePreview("lulla-log.csv")) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    Button("Erase all entries", role: .destructive) { confirmReset = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.lullaCream)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Erase every logged entry? Your baby's profile stays.", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase all entries", role: .destructive) { model.mutate { $0.entries.removeAll() } }
            }
            .onAppear {
                guard !loaded, let p = model.data.profile else { return }
                profile = p
                bornEarly = p.dueDate != nil
                loaded = true
            }
            .onChange(of: profile) { _, new in save(new) }
            .onChange(of: bornEarly) { _, early in
                if !early { profile.dueDate = nil } else if profile.dueDate == nil {
                    profile.dueDate = profile.birthDate.addingTimeInterval(28 * 86400)
                }
            }
            .onChange(of: profile.napAlerts) { _, on in
                if on { Task { await NapAlerts.requestPermission() } }
            }
        }
        .tint(.lullaInk)
    }

    private func save(_ p: BabyProfile) {
        guard loaded, p != model.data.profile else { return }
        model.mutate { $0.profile = p }
    }

    private func range(_ r: ClosedRange<Double>) -> String {
        "\(Format.minutes(r.lowerBound))–\(Format.minutes(r.upperBound))"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(Color.lullaMuted)
        }
    }

    private func help(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.medium))
            Text(text).font(.footnote).foregroundStyle(Color.lullaMuted)
        }
        .padding(.vertical, 2)
    }
}

/// The whole log as CSV, for spreadsheets or a pediatrician visit.
struct CSVExport: Transferable {
    let data: LogData

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.csv.utf8)
        }
        .suggestedFileName("lulla-log.csv")
    }

    var csv: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = .current
        var lines = ["type,start,end,duration_min,method,side,amount_ml,contents,diaper,note"]
        for e in data.entries {
            let fields: [String] = [
                e.kind.rawValue,
                iso.string(from: e.start),
                e.end.map { iso.string(from: $0) } ?? "",
                e.end.map { String(Int(($0.timeIntervalSince(e.start) / 60).rounded())) } ?? "",
                e.feedMethod?.rawValue ?? "",
                e.side?.rawValue ?? "",
                e.amountML.map { String(Int($0.rounded())) } ?? "",
                e.bottleContent?.rawValue ?? "",
                e.diaper?.rawValue ?? "",
                (e.note ?? "").replacingOccurrences(of: "\"", with: "\"\""),
            ]
            lines.append(fields.map { $0.contains(",") || $0.contains("\"") || $0.contains("\n") ? "\"\($0)\"" : $0 }
                .joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

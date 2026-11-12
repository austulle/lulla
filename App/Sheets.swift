import SwiftUI

extension VolumeUnit {
    /// Rounded to what the editors show: whole ml, or 0.1 oz.
    func display(_ ml: Double) -> Double { self == .ml ? ml.rounded() : (ml / Self.mlPerOz * 10).rounded() / 10 }
    func toML(_ value: Double) -> Double { self == .ml ? value : value * Self.mlPerOz }
    var step: Double { self == .ml ? 10 : 0.5 }
    var label: String { rawValue }
}

/// Sheet chrome: cream background, serif title, close button.
private struct SheetFrame<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.lullaSerif(30)).foregroundStyle(Color.lullaInk)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.lullaInk)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.lullaInk.opacity(0.07)))
                }
            }
            content
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.lullaCream.ignoresSafeArea())
    }
}

// MARK: - Feed

struct FeedSheet: View {
    @Environment(LogModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var method: FeedMethod = .breast
    @State private var amount: Double = 120
    @State private var content: BottleContent = .formula
    @State private var time = Date()
    @State private var note = ""
    @State private var didLoad = false

    private var unit: VolumeUnit { model.data.profile?.volumeUnit ?? .ml }

    var body: some View {
        SheetFrame(title: "Feed") {
            Picker("Type", selection: $method) {
                Text("Breast").tag(FeedMethod.breast)
                Text("Bottle").tag(FeedMethod.bottle)
                Text("Solids").tag(FeedMethod.solids)
            }
            .pickerStyle(.segmented)

            switch method {
            case .breast: breast
            case .bottle: bottle
            case .solids: solids
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            let profile = model.data.profile
            if profile?.feedingStyle == .bottle { method = .bottle }
            amount = unit.display(profile?.defaultBottleML ?? 120)
        }
    }

    private var breast: some View {
        let suggested = model.data.suggestedSide
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ForEach(BreastSide.allCases, id: \.self) { side in
                    Button {
                        model.mutate { $0.startBreast(side, at: Date()) }
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 22) {
                            HStack {
                                MonoLabel(side.title)
                                Spacer()
                                if side == suggested { Tag("Next") }
                            }
                            Text(side.short).font(.lullaSerif(56))
                        }
                        .foregroundStyle(Color.lullaInk)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(side == suggested
                                      ? AnyShapeStyle(MeshGradient(width: 2, height: 2,
                                                                   points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                                                                   colors: [Color(hex: 0xFBE3C4), Color(hex: 0xF6B8C8),
                                                                            Color(hex: 0xDDEB9C), Color(hex: 0xF4C6D2)]))
                                      : AnyShapeStyle(Color.lullaInk.opacity(0.05)))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Starts a timer. Switch sides from the timer card; the side you end on decides the next suggestion.")
                .font(.system(size: 13))
                .foregroundStyle(Color.lullaMuted)
            Button("Log a past feed instead") { router.sheet = .add(.feed) }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.lullaInk)
        }
    }

    private var bottle: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                stepButton("minus") { amount = max(0, amount - unit.step) }
                Spacer()
                VStack(spacing: 2) {
                    Text(unit == .ml ? "\(Int(amount))" : String(format: "%.1f", amount))
                        .font(.lullaSerif(56))
                        .monospacedDigit()
                    MonoLabel(unit.label)
                }
                Spacer()
                stepButton("plus") { amount += unit.step }
            }
            Picker("Contents", selection: $content) {
                ForEach(BottleContent.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            DatePicker("Time", selection: $time, in: ...Date().addingTimeInterval(300))
                .font(.system(size: 15))
            Button("Save bottle") {
                let ml = unit.toML(amount)
                model.mutate { $0.add(.bottle(ml: ml, content: content, at: time)) }
                dismiss()
            }
            .buttonStyle(InkButtonStyle())
            .disabled(amount <= 0)
        }
    }

    private var solids: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("What did they eat? (optional)", text: $note)
                .textFieldStyle(.roundedBorder)
            DatePicker("Time", selection: $time, in: ...Date().addingTimeInterval(300))
                .font(.system(size: 15))
            Button("Save") {
                let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
                model.mutate { $0.add(.solids(at: time, note: text.isEmpty ? nil : text)) }
                dismiss()
            }
            .buttonStyle(InkButtonStyle())
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.lullaInk)
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(Color.lullaInk.opacity(0.3), lineWidth: 1))
        }
        .buttonRepeatBehavior(.enabled)
    }
}

// MARK: - Diaper

struct DiaperSheet: View {
    @Environment(LogModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()

    var body: some View {
        SheetFrame(title: "Diaper") {
            HStack(spacing: 10) {
                ForEach(DiaperKind.allCases, id: \.self) { kind in
                    Button {
                        model.mutate { $0.add(.diaper(kind, at: time)) }
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: symbol(kind)).font(.system(size: 20, weight: .light))
                            Text(kind.title).font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(Color.lullaInk)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.lullaInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            DatePicker("Time", selection: $time, in: ...Date().addingTimeInterval(300))
                .font(.system(size: 15))
        }
        .presentationDetents([.height(300)])
    }

    private func symbol(_ k: DiaperKind) -> String {
        switch k {
        case .wet: "drop"
        case .dirty: "circle.fill"
        case .mixed: "circle.lefthalf.filled"
        }
    }
}

// MARK: - Edit / add

struct EntryEditor: View {
    @Environment(LogModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var entry: Entry
    @State private var ongoing: Bool
    @State private var endDate: Date
    @State private var amount: Double = 0
    @State private var confirmDelete = false
    let isNew: Bool

    init(entry: Entry, isNew: Bool) {
        _entry = State(initialValue: entry)
        _ongoing = State(initialValue: entry.end == nil)
        _endDate = State(initialValue: entry.end ?? Date())
        self.isNew = isNew
    }

    static func blank(_ kind: EntryKind) -> Entry {
        let now = Date()
        switch kind {
        case .sleep: return .sleep(start: now.addingTimeInterval(-3600), end: now)
        case .feed: return .breast(.left, start: now.addingTimeInterval(-15 * 60), end: now)
        case .diaper: return .diaper(.wet, at: now)
        }
    }

    private var unit: VolumeUnit { model.data.profile?.volumeUnit ?? .ml }
    private var isTimed: Bool { entry.kind == .sleep || (entry.kind == .feed && entry.feedMethod == .breast) }

    /// Only one timer of each kind may run.
    private var canBeOngoing: Bool {
        let running = entry.kind == .sleep ? model.data.activeSleep : model.data.activeFeed
        return running == nil || running?.id == entry.id
    }

    private var title: String { (isNew ? "Add " : "Edit ") + entry.kind.rawValue }

    private var isValid: Bool { !isTimed || ongoing || endDate >= entry.start }

    var body: some View {
        NavigationStack {
            Form {
                switch entry.kind {
                case .sleep:
                    Section { timedFields }
                case .feed:
                    Section {
                        Picker("Type", selection: Binding(
                            get: { entry.feedMethod ?? .breast },
                            set: { entry.feedMethod = $0; if $0 == .breast, entry.side == nil { entry.side = .left } }
                        )) {
                            Text("Breast").tag(FeedMethod.breast)
                            Text("Bottle").tag(FeedMethod.bottle)
                            Text("Solids").tag(FeedMethod.solids)
                        }
                        switch entry.feedMethod ?? .breast {
                        case .breast:
                            Picker("Side", selection: Binding(get: { entry.side ?? .left }, set: { entry.side = $0 })) {
                                ForEach(BreastSide.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            timedFields
                        case .bottle:
                            Stepper(value: $amount, in: 0...1000, step: unit.step) {
                                Text("Amount  \(unit == .ml ? "\(Int(amount)) ml" : String(format: "%.1f oz", amount))")
                            }
                            Picker("Contents", selection: Binding(get: { entry.bottleContent ?? .formula },
                                                                  set: { entry.bottleContent = $0 })) {
                                ForEach(BottleContent.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            DatePicker("Time", selection: $entry.start)
                        case .solids:
                            DatePicker("Time", selection: $entry.start)
                        }
                    }
                case .diaper:
                    Section {
                        Picker("Type", selection: Binding(get: { entry.diaper ?? .wet }, set: { entry.diaper = $0 })) {
                            ForEach(DiaperKind.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        DatePicker("Time", selection: $entry.start)
                    }
                }

                Section("Note") {
                    TextField("Optional", text: Binding(get: { entry.note ?? "" },
                                                        set: { entry.note = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                }

                if !isNew {
                    Section {
                        Button("Delete entry", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.lullaCream)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    model.mutate { $0.delete(id: entry.id) }
                    dismiss()
                }
            }
            .onAppear { amount = unit.display(entry.amountML ?? model.data.profile?.defaultBottleML ?? 120) }
        }
        .tint(.lullaInk)
    }

    @ViewBuilder private var timedFields: some View {
        DatePicker("Start", selection: $entry.start)
        if canBeOngoing {
            Toggle(entry.kind == .sleep ? "Still asleep" : "Still feeding", isOn: $ongoing)
        }
        if !ongoing || !canBeOngoing {
            DatePicker("End", selection: $endDate, in: entry.start...)
            Text("Duration  \(Format.duration(endDate.timeIntervalSince(entry.start)))")
                .foregroundStyle(Color.lullaMuted)
        }
    }

    private func save() {
        var e = entry
        switch e.kind {
        case .sleep:
            e.end = (ongoing && canBeOngoing) ? nil : endDate
            e.feedMethod = nil
        case .feed:
            switch e.feedMethod ?? .breast {
            case .breast:
                e.feedMethod = .breast
                e.end = (ongoing && canBeOngoing) ? nil : endDate
                e.amountML = nil
            case .bottle:
                e.end = e.start
                e.side = nil
                e.amountML = unit.toML(amount)
            case .solids:
                e.end = e.start
                e.side = nil
                e.amountML = nil
            }
        case .diaper:
            e.end = e.start
        }
        model.mutate { $0.update(e) }
        dismiss()
    }
}

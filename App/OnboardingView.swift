import SwiftUI

struct OnboardingView: View {
    @Environment(LogModel.self) private var model
    @State private var name = ""
    @State private var birthDate = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? Date()
    @State private var bornEarly = false
    @State private var dueDate = Date()
    @State private var style: FeedingStyle = .breast
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            GradientBackdrop(mood: .awake).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MonoLabel("Lulla", color: .lullaForest)
                    Spacer()
                    MonoLabel("01", color: .lullaForest)
                }
                .padding(.top, 12)

                Spacer(minLength: 12)

                OrbitMark(color: .lullaForest)
                    .frame(width: 150, height: 110)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 12)

                Text("Sleep, feeds,\nand the next\nnap window.")
                    .font(.lullaSerif(40))
                    .foregroundStyle(Color.lullaForest)
                    .padding(.bottom, 18)

                CreamPanel(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        MonoLabel("About your baby")
                        TextField("Name", text: $name)
                            .font(.lullaSerif(24))
                            .focused($nameFocused)
                            .submitLabel(.done)
                        DashedRule()
                        DatePicker("Born", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                        Toggle("Born early", isOn: $bornEarly)
                        if bornEarly {
                            DatePicker("Due date", selection: $dueDate, in: birthDate..., displayedComponents: .date)
                        }
                        Picker("Feeding", selection: $style) {
                            ForEach(FeedingStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Button("Begin") { finish() }
                            .buttonStyle(InkButtonStyle())
                            .padding(.top, 4)
                    }
                    .font(.system(size: 15))
                    .tint(.lullaInk)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .onChange(of: bornEarly) { _, early in
            if early, dueDate <= birthDate { dueDate = birthDate.addingTimeInterval(28 * 86400) }
        }
    }

    private func finish() {
        var profile = BabyProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  birthDate: birthDate,
                                  dueDate: bornEarly && dueDate > birthDate ? dueDate : nil)
        profile.feedingStyle = style
        if Locale.current.measurementSystem == .us {
            profile.volumeUnit = .oz
            profile.defaultBottleML = 4 * VolumeUnit.mlPerOz
        }
        model.mutate { $0.profile = profile }
        Task { await NapAlerts.requestPermission() }
    }
}

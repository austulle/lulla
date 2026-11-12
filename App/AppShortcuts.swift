import AppIntents

/// Zero-setup Siri phrases and Shortcuts-app tiles. Each also shows up for
/// the Action button and Spotlight.
struct LullaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSleepIntent(),
            phrases: [
                "Start sleep in \(.applicationName)",
                "Baby is asleep in \(.applicationName)",
                "\(.applicationName) start nap",
            ],
            shortTitle: "Start Sleep",
            systemImageName: "moon.zzz"
        )
        AppShortcut(
            intent: EndSleepIntent(),
            phrases: [
                "End sleep in \(.applicationName)",
                "Baby is awake in \(.applicationName)",
                "\(.applicationName) wake up",
            ],
            shortTitle: "End Sleep",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: PauseSleepIntent(),
            phrases: [
                "Pause sleep in \(.applicationName)",
                "Resume sleep in \(.applicationName)",
            ],
            shortTitle: "Pause Sleep",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: StartBreastfeedingIntent(),
            phrases: [
                "Start feeding in \(.applicationName)",
                "Start breastfeeding in \(.applicationName)",
                "Start feeding on \(\.$side) in \(.applicationName)",
            ],
            shortTitle: "Start Feeding",
            systemImageName: "drop"
        )
        AppShortcut(
            intent: StopFeedingIntent(),
            phrases: [
                "Stop feeding in \(.applicationName)",
                "Done feeding in \(.applicationName)",
            ],
            shortTitle: "Stop Feeding",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: PauseFeedingIntent(),
            phrases: [
                "Pause feeding in \(.applicationName)",
                "Resume feeding in \(.applicationName)",
            ],
            shortTitle: "Pause Feeding",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: LogBottleIntent(),
            phrases: [
                "Log a bottle in \(.applicationName)",
                "Log bottle in \(.applicationName)",
            ],
            shortTitle: "Log Bottle",
            systemImageName: "waterbottle"
        )
        AppShortcut(
            intent: NextNapIntent(),
            phrases: [
                "When is the next nap in \(.applicationName)",
                "Next nap in \(.applicationName)",
                "\(.applicationName) next nap",
            ],
            shortTitle: "Next Nap",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: LastFeedIntent(),
            phrases: [
                "When was the last feed in \(.applicationName)",
                "Last feed in \(.applicationName)",
            ],
            shortTitle: "Last Feed",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}

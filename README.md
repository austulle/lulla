# Lull

A small native iOS app for tracking a baby's sleep, feeds and diapers.
It shows the next nap window, has widgets for the Home Screen and Lock
Screen, controls for Control Center, Live Activities, and Siri / Shortcuts
actions.

SwiftUI, iOS 18+, no third-party dependencies, no account and no server.
All data is stored in one JSON file in the App Group, on the device.

## Build

```bash
git clone https://github.com/austulle/lulla && cd lulla
brew install xcodegen      # once
xcodegen generate
open Lull.xcodeproj        # or:
xcodebuild -project Lull.xcodeproj -scheme Lull \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Signing uses team `Y3V978URTC` with bundle ids `com.lull.baby` and
`com.lull.baby.widgets` and App Group `group.com.lull.baby`. To use your own
ids, change all three in `project.yml` and set `LogStore.appGroup` to match.
Xcode's automatic signing registers the App Group the first time you build.

The core logic (`Core/`) is plain Foundation. Its 17 tests also run on Linux
with SwiftPM: point a package target named `Lull` at `Core/` and a test
target at `Tests/`.

## How the nap window works (`Core/NapPredictor.swift`)

1. **Age band.** `Core/WakeWindows.swift` holds typical wake windows by age,
   from 0–4 weeks up to 2–3 years. Each band has a naps-per-day count, a
   first-of-day window and a before-bedtime window. The windows in between
   are interpolated, so they get longer through the day. If a due date is
   set, the band uses corrected age until 2 years.
2. **Position in the day.** Sleep that starts between 19:00 and 06:00 counts
   as night, and so does a sleep of 3 hours or more that starts after 17:00.
   Waking up from the night between 04:00 and 12:00 opens window 0. After a
   nap, the window number is the count of naps since that morning's wake-up.
   Once the day's naps are used up, the next window is **bedtime**. From 3
   months on, a nap that would start after 18:00 also becomes bedtime. A
   night waking gets no window.
3. **Short nap.** If the previous nap was under 40 minutes, the next window
   is 15% shorter.
4. **Personal tuning.** The app looks at the last 7 days of wake windows that
   ended in a good sleep (a nap of 40+ minutes, or the night). It takes the
   median of observed ÷ expected. Once there are 3 such samples, that median
   is blended in, up to 50% weight at 10 samples. The ratio is capped at
   0.8–1.25.
5. **Window.** The target is ±8% of the wake window, with a minimum of ±10
   and a maximum of ±20 minutes. It is clamped to 80–120% of the age-typical
   range.

The windows are estimates, not medical advice, and the app says so in
Settings.

## Surfaces

| Surface | Where |
|---|---|
| Home Screen widget, small and medium (with Sleep / Feed / Diaper buttons) | `Widgets/LullWidget.swift` |
| Lock Screen widgets: circular gauge to the next window, rectangular, inline | `Widgets/LullWidget.swift` |
| Control Center and Lock Screen corner controls: Sleep and Feed toggles | `Widgets/LullWidgetBundle.swift` |
| Live Activity and Dynamic Island for running sleep or feed timers, with buttons | `Widgets/LullLiveActivity.swift` |
| Siri phrases and Shortcuts actions (start/end sleep, start/stop feeding, log bottle, log diaper, next nap, last feed) | `Shared/Intents.swift`, `App/AppShortcuts.swift` |
| Nap-window notification, sent N minutes before the window opens | `Shared/LullActions.swift` (`NapAlerts`) |
| Deep links: `lull://feed`, `lull://diaper`, `lull://history` | `App/LullApp.swift` |

Every write goes through `LullActions.perform` or `LogModel.mutate`. That
path takes a file lock (`flock`) and does a read-modify-write of the shared
JSON. It then reloads widgets and controls, syncs Live Activities,
reschedules the nap alert, and posts a Darwin notification so the open app
reloads. Intents that change a timer are `LiveActivityIntent`s, so they run
in the app process even when tapped from a widget. That matters because
Live Activities can only be started from the app process.

## Layout

```
Core/      models, JSON store, wake-window table, predictor, snapshot, formatting
Shared/    theme, App Intents, Live Activity attributes and sync, write path
App/       SwiftUI app: Today, feed/diaper sheets, editor, history, settings, onboarding
Widgets/   WidgetKit extension: widgets, controls, Live Activity
Tests/     predictor and store tests
```

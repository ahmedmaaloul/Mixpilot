# Mixpilot

A macOS menu bar app that sets the volume of each app separately, like the volume mixer on Windows.
Main use case: during a call, keep the call loud and everything else quiet. English and German,
following the system language. Distributed outside the App Store (Developer ID, notarized).
macOS 14.4 or newer. One dependency, approved by the user: KeyboardShortcuts 3.1.0 (see Dependencies).

## Layout

```
Mixpilot.xcodeproj           Open this. App target, local package, KeyboardShortcuts (exact 3.1.0).
                             Package.resolved is committed (project.xcworkspace/xcshareddata/swiftpm).
Config/Base.xcconfig         Bundle ID base (app.mixpilot → app.mixpilot.mac), team, version.
Info.plist                   Partial plist (usage descriptions); the rest comes from build settings.
Mixpilot/                    App target (UI and wiring only), folder-synchronized group
  App/                       @main + AppDelegate, MixerModel (state for the UI), AppDirectory (names,
                             icons), PreviewData, SnapshotRenderer (debug: previews → PNG)
  MenuBar/                   MixerPanel (the window-style menu bar extra), AppRow, MenuBarIcon
  Settings/                  SettingsView (General, Calls, Apps, Shortcuts panes), LoginItem,
                             Shortcuts (names + handlers), AppWindows (open Settings, About + credits)
  Onboarding/                OnboardingView (welcome → permission → done)
  Resources/                 Localizable.xcstrings, InfoPlist.xcstrings, AppIcon.icon (Icon Composer),
                             PrivacyInfo.xcprivacy (UserDefaults CA92.1, systemUptime 35F9.1)
MixpilotKit/                 Swift package, no UI
  Sources/MixpilotCore/      Pure logic, fully tested: AppGrouper, Linger, AppAudioSettings,
                             AppSettingsStore, OutputDevice (+ kind), TapPlanner, CallMode + KnownCallApps
  Sources/MixpilotRender/    C: the audio thread's code (MPRenderIOProc, gain ramp + call-mode fade,
                             both capped at 1)
  Sources/MixpilotAudio/     Core Audio HAL: HAL helpers, ProcessMonitor, DeviceMonitor, Responsibility
                             (private SPI), AudioDevices, TapSession (+ Output), TapManager,
                             MicrophoneController
  Tests/MixpilotCoreTests/   Swift Testing: grouping, linger, tap planning, settings storage, device kinds,
                             call detection
  Tests/MixpilotRenderTests/ Swift Testing against the C kernel with synthetic buffers
Localization/                de.py (German table, source of truth) + localize.py (sync + fill + check);
                             KeyboardShortcuts/de.lproj: our German for the dependency's recorder
scripts/                     build.sh, run.sh, snapshots.sh, debug-volume.swift (drive a debug build
                             without the panel), localize-dependencies.sh (build phase), release-mac.sh
website/                     mixpilot.blitzraum.com: build.py (texts EN/DE) + assets/ → public/ (static)
docs/images/                 Icon and screenshots for the README
README.md, README.de.md      Project README in English and German
LICENSE.md                   PolyForm Noncommercial 1.0.0 (commercial use only with the user's permission)
```

The `.xcodeproj` uses folder-synchronized groups: any file under `Mixpilot/` is in the target
automatically. Don't add per-file entries to `project.pbxproj`.

## Architecture

```
Core Audio HAL ── listeners (process list, per process IsRunning + Devices) on one serial queue
   ▼
ProcessMonitor ──► [ProcessSnapshot] ──► AppGrouper (helpers → owning app) ──► MixerModel (@MainActor)
                                                                                 │
                                 TapManager ◄── TapRequest per app: gain = volume × mute (× duck, M4)
                                 ▼          (own queue; decisions from TapPlanner, pure + tested)
          TapSession = private process tap (.mutedWhenTapped) + private aggregate device + C IOProc
```

- **Process discovery.** `kAudioHardwarePropertyProcessObjectList` on the system object lists every
  HAL client. Each process object has PID, bundle ID, `IsRunningOutput`, `IsRunningInput`, `Devices`.
  `ProcessMonitor` listens to the list and, per process, to `IsRunning` and `Devices` (see pitfalls),
  re-reads both running flags, coalesces bursts (50 ms) and publishes snapshots through an `AsyncStream`.
- **Grouping helpers under their app** (`AppGrouper`, pure and tested). Order of rules:
  1. the process is itself a running app;
  2. its *responsible* PID is a running app (`Responsibility.swift`: private
     `responsibility_get_pid_responsible_for_pid`, looked up with `dlsym`, nil if missing). This is the
     only way to map XPC services like `com.apple.WebKit.GPU` to Safari or Mail;
  3. its parent PID is a running app (Chrome/Electron helpers);
  4. its bundle ID starts with a running app's bundle ID + "." (`net.whatsapp.WhatsApp.ServiceExtension`).
  Checked first: call daemons (`AppGrouper.daemonOwners`): `avconferenced` and `callservicesd`
  (TelephonyUtilities) do FaceTime's and Phone's audio and belong to whichever of those runs.
  Processes without an owning app are hidden, and so are background-only apps
  (`activationPolicy == .prohibited`). Mixpilot hides itself.
- **Rows linger** 3 s after an app stops playing so the list doesn't jump; order is alphabetical.
- **Apps you haven't touched are never tapped**: no added latency, no risk. A session exists while
  the app's gain ≠ 1, plus 3 s after it returns to 1 (`TapPlanner.unityGrace`) so dragging through
  100 % doesn't rebuild it.
- **TapSession** = one tap for the session's whole life + a replaceable `Output`.
  Tap: `CATapDescription(stereoMixdownOfProcesses:)` over all the app's process objects, private,
  `.mutedWhenTapped`. Output: private aggregate device (main sub-device = the output device, the tap
  with drift compensation), wait until its streams exist, `AudioDeviceCreateIOProcID` with the C
  `MPRenderIOProc` and an opaque `MPRenderState*` (C11 atomics: target gain, signal flag, callback
  count). Output teardown: stop → destroy IOProc → destroy aggregate → free state; tap last.
- **Switching devices** (`setOutput`) is make-before-break: the new output starts, then the old one is
  destroyed, so the app is never heard unmuted on its own device in between.
- **IO follows the app's stream**: audio runs only while the app has an open output stream
  (`start`/`stop` actions), so Mixpilot never keeps a device (AirPods) streaming silence.
  New helper processes are added by rewriting `kAudioTapPropertyDescription` (no gap).
- **Output device**: the chosen device (`AppAudioSettings.outputDeviceUID`) while it is connected,
  else the device the app plays to (`kAudioProcessPropertyDevices`, output scope), else the system
  default. A chosen device makes the app "rerouted": tapped even at 100 %. When it disconnects, the
  app follows the system again; when it reconnects, the choice applies again (UIDs are stable).
- **Device health**: listeners on the aggregate, the output device (IsAlive, nominal sample rate) and
  the tap format only *trigger a check*; the output is rebuilt (in place, keeping the tap) only when a
  device is gone or not alive, after re-planning (which may move it elsewhere). A 2 s watchdog
  rebuilds an output whose callback count stopped growing. More than 3 rebuilds in 10 s → release
  the app for 10 s.
- **Saved settings**: `AppSettingsStore` keeps volume, mute and chosen device (+ its name, to show
  "AirPods Pro (Not Connected)") per bundle ID as JSON in UserDefaults (`appAudioSettings.v1`).
  Unchanged apps and `pid:` IDs aren't stored; loading is lenient (bad values repaired or dropped).
  Settings apply as soon as the app shows up in Core Audio again.
- **Call mode** (`CallMode`, pure): a call is detected when a known call app or browser
  (`KnownCallApps`) uses the microphone for 1 s, and ends 5 s after none does (muting yourself
  briefly doesn't end it). The panel switch (and the M5 shortcut) overrides detection until a call
  starts or ends. While on, every app except the call apps and anything using the microphone gets
  `duck = callModeLevel` (UserDefaults `callModeLevel`, default 0.2; Settings in M5). Duck is a
  second gain stage in the C kernel with its own slow fade (τ 0.15 s down, 0.35 s up) so user volume
  changes stay instant during a call and volumes come back exactly. Apps lowered only by call mode
  are tapped when they play (not every app with an audio process); the 3 s grace covers the fade up.
- **Microphone** (`MicrophoneController`): always the default input device. Mute uses the device's
  mute switch if settable, else volume 0 with the old level saved. The mute moves with the input
  device. It never outlives Mixpilot: restored at quit/SIGTERM (`stopAudio`); after a crash the
  record in UserDefaults `mutedInputDevices` (UID → -1 for the switch or the saved volume) is undone
  at the next launch (`restoreLeftovers`). Input volume = `kAudioDevicePropertyVolumeScalar`
  (input scope, main element or channels 1–2); hidden if not settable.
- **Menu bar icon**: `mic.slash` while the microphone is off (most important), `phone` while call
  mode is on, else `slider.vertical.3`.
- **Volume**: 0–100 %, where 100 % is the app's own level. **No boost, by the user's decision: Mixpilot
  only makes apps quieter, to protect hearing and speakers ("we are not Windows").** Enforced twice:
  `AppAudioSettings.volumeRange` is 0…1 (stored values above are clamped on load) and the C kernel
  clamps every gain to 1. Don't add amplification back without asking.
- **Fail open**: on any error the session is destroyed and the app is blocked for 10 s;
  `.mutedWhenTapped` then gives the app its sound back. Permission: 2 s after a start with only
  silence, rewrite the tap description; `kAudioDevicePermissionsError` → release everything, show the
  notice, probe every 3 s with an unmuted, unread global tap until granted.
- **Quitting**: `applicationWillTerminate` and SIGTERM/SIGINT/SIGHUP (dispatch signal sources) call
  `TapManager.stopAll()` (synchronous). A crash or `kill -9` needs nothing: private taps and aggregate
  devices vanish with the process (verified). `TapManager.removeLeftovers()` at launch removes any
  non-private objects named/UID'd as Mixpilot's.

## Design rules (from the brief; these are requirements)

- Look and feel 100 % native, as if Apple made it. Follow the macOS HIG; when unclear, copy Control
  Center, the Sound settings pane or the built-in menu bar extras.
- Only native SwiftUI/AppKit controls (Slider, Toggle, Picker, Menu, Form, List). No custom-drawn
  sliders, buttons or switches. No custom ButtonStyles that draw backgrounds.
- `MenuBarExtra` with `.window` style (HIG: a popover only when a menu is too complex — per-app
  sliders are). Width ≈ Control Center (320 pt). The system draws the panel's material, corner radius
  and Liquid Glass: never paint opaque backgrounds.
- Menu bar icon: monochrome SF Symbol as a template (`slider.vertical.3`); it changes to show call
  mode and a muted microphone.
- HIG: people decide whether the extra is in the menu bar → "Show in Menu Bar" setting; reopening the
  app (Finder/Spotlight) opens Settings. Don't rely on the extra being visible (macOS 27 folds extras
  into an overflow): shortcuts are the second way in.
- macOS 27 hides most menu item images: icons in menus only for devices (output picker). Action items
  are text only.
- Materials: system only. Liquid Glass on macOS 26+ comes from standard controls and containers.
- Typography: system font, text styles only (headline, body, subheadline, caption). No fixed sizes.
  `.monospacedDigit()` is fine for percentages.
- Color: semantic colors only (`.primary`, `.secondary`, `.tint`, `Color(nsColor: .labelColor)` …).
  Respect the accent color. No hex colors (app icon excepted).
- SF Symbols everywhere; volume uses `speaker.wave.3` with `variableValue`. Real app icons from
  NSWorkspace.
- Settings: SwiftUI `Settings` scene, toolbar tabs, `.formStyle(.grouped)`, "Settings" not
  "Preferences", changes apply instantly, opens on the last pane.
- Accessibility: VoiceOver label + value on every control, full keyboard navigation, Increase
  Contrast, Reduce Transparency, Reduce Motion, Dynamic Type where macOS supports it.
- Motion: only subtle system animations, none with Reduce Motion. No bounces, no custom transitions.
- Light and dark mode both perfect.
- German is ~30 % longer: layouts must wrap, never truncate or overlap. Apple's German terms:
  Einstellungen, Ausgabegerät, Ton aus, Lautstärke, Mikrofon, Eingangslautstärke, Beenden, „…“,
  informal "du", space before the ellipsis ("Einstellungen …").
- Copy: short, calm, clear. No exclamation marks, no jargon ("process tap", "aggregate device") in UI.
- App icon: Icon Composer (`AppIcon.icon`), layered, default/dark/clear/tinted.

## Core Audio pitfalls (keep adding)

- No public API reads the System Audio Recording permission. Signals: updating
  `kAudioTapPropertyDescription` returns `kAudioDevicePermissionsError` when denied; a denied tap
  delivers silence. The prompt appears the first time an aggregate device containing a tap starts.
- `NSAudioCaptureUsageDescription` must be in `Info.plist` itself (the `INFOPLIST_KEY_` build setting
  is reported to be ignored for it).
- After creating an aggregate device, wait until it is ready before starting the IOProc, or audio can
  fail silently.
- FaceTime call audio runs in `avconferenced`/`callservicesd`, not in FaceTime itself (seen in the
  process list) → call detection needs a daemon → app mapping (M4).
- `kAudioProcessPropertyIsRunningOutput` / `IsRunningInput` **never send change notifications**
  (macOS 27). Listen to `kAudioProcessPropertyIsRunning` (global scope) and
  `kAudioProcessPropertyDevices` (wildcard scope) and re-read the flags.
- `IsRunningOutput` means "has an active output stream", not "is audible": QuickTime keeps its stream
  ~10 s after pausing, Chrome similar. Rows follow the stream (plus the 3 s linger).
- The responsible-PID SPI exists on macOS 27 and maps `com.apple.WebKit.GPU` → Mail/Safari; Chrome
  and Electron helpers also have the app as parent.
- macOS 26 added `CATapDescription.bundleIDs` and `processRestoreEnabled` (not usable on 14.4).
- The first tap start shows the System Audio Recording prompt (~2 s until the user answers). After
  that, creating a session and starting it takes ~50–90 ms.
- When an app reopens its stream after a long pause, its first ~100 ms play at its own level until
  `start` runs (`.mutedWhenTapped` only mutes while read). Accepted for fail-open safety; `.muted`
  would avoid it but could leave an app silent if Mixpilot stalls.
- Privacy pane URL: `x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture`
  opens "Screen & System Audio Recording" (Mixpilot is under "System Audio Recording Only").
- Swift: `AudioBufferList.allocate(maximumBuffers: 0)` traps; allocate 1 and set `count = 0`.
- **Destroying a tap and creating a new one for the same processes right away blocks ~1.3 s and
  returns noErr with tap ID 0** (macOS 27). Hence: device switches/rebuilds keep the tap, the
  manager waits 1.5 s (`recreateDelay`) after releasing an app before tapping it again, and a tap ID
  of 0 is treated as an error.
- A new aggregate device sends IsAlive / sample-rate notifications while it settles: never rebuild on
  a notification alone, check the actual state (`isBroken`), or rebuilds loop.
- Apple's wording for following the system output is "Use System Setting" (FaceTime's Video menu);
  German "Systemeinstellung verwenden".
- `avconferenced` and TelephonyUtilities are listed in `NSWorkspace.runningApplications`
  (background-only), so a plain "own PID is an app" rule would show them as rows.
- TCC asks the *responsible* process: a binary started from a terminal
  (`Mixpilot.app/Contents/MacOS/Mixpilot …`) is checked against the terminal's permission, not
  Mixpilot's. Always `open` the app to test permissions; snapshots (started that way) show the
  permission as missing.
- Mic Modes (Standard / Voice Isolation / Wide Spectrum) are per app, set by the user in Control
  Center; no public API reads or sets another app's mode, so Mixpilot doesn't offer it. The mic mute
  (device level, before any app's processing) and the input volume (the device's hardware level,
  like Sound settings) don't change the chosen mode. Apps with voice processing may also make macOS
  lower other audio during calls, which stacks with call mode.
- The built-in microphone has a settable input mute (`kAudioDevicePropertyMute`, input scope, main
  element); after `kill -9` it stays muted until Mixpilot runs again (hence launch at login, M5).

## Build, run, test

- Xcode 27 (Swift 6.4). Deployment target macOS 14.4. This Mac runs macOS 27 only: older-OS
  fallbacks need a VM to verify.
- Tests: `cd MixpilotKit && swift test` (all logic and the C kernel live in the package; Xcode
  doesn't run a project's local-package tests from the app scheme — open `MixpilotKit/` in Xcode instead).
- App: `xcodebuild -project Mixpilot.xcodeproj -scheme Mixpilot -derivedDataPath build/DerivedData -allowProvisioningUpdates build`
  then `open build/DerivedData/Build/Products/Debug/Mixpilot.app` (or `scripts/run.sh`).
- Signing: team `NSRXRUC9KF`, automatic, in `Config/Base.xcconfig`. A stable signature keeps the
  System Audio Recording permission across rebuilds.
- Test German: `scripts/run.sh -AppleLanguages "(de)"`.
- Logs: `log stream --level info --predicate 'subsystem == "app.mixpilot.mac"'` (category `taps`
  shows every session created, paused, resumed, released).
- Without the panel (debug build): `swiftc -O scripts/debug-volume.swift -o build/debug-volume`, then
  `build/debug-volume com.apple.QuickTimePlayerX 0.3` (0…1, `mute`, `unmute`,
  `device <UID>`, `device system`), `build/debug-volume - callmode on|off`,
  `build/debug-volume - mic mute|unmute`. Device UIDs: `system_profiler SPAudioDataType` doesn't show them;
  the debug log shows `Tapping … on <UID>`.
- Saved settings: `defaults read app.mixpilot.mac appAudioSettings.v1` (JSON data);
  `defaults delete app.mixpilot.mac appAudioSettings.v1` resets them.

## Conventions

- Swift 6 language mode. App target: default actor isolation `MainActor` + Approachable Concurrency.
  Package: nonisolated by default + `NonisolatedNonsendingByDefault`. Core Audio state lives on one
  serial queue per owner (`@unchecked Sendable` classes that touch state only on that queue).
- Real-time code (IOProc) is C in `MixpilotRender` (M2): no allocation, locks, ObjC/Swift calls or
  logging on the audio thread. Parameters cross threads through C11 atomics.
- Logic goes in `MixpilotCore` with tests; the app contains UI and platform glue.
- Comments in English; doc comments on types and non-obvious functions.
- Strings: write English literals in `Text`/`Button`/`Label`/`String(localized:)`, add German to
  `Localization/de.py`, run `python3 Localization/localize.py` (builds, syncs the catalog from the
  compiler's `.stringsdata`, fills German, fails on anything missing). Don't edit catalogs in Xcode.
  Never `cond ? "A" : "B"` for UI text; use `cond ? Text("A") : Text("B")`.
- Every view gets `#Preview`s in light/dark × English/German. `scripts/snapshots.sh` renders the
  `SnapshotRenderer.catalog` to `build/snapshots/` (light + dark, English + German) for review; add new
  views to the catalog. Snapshots draw on the window background (= Reduce Transparency look).
- The live panel can't be opened programmatically on macOS 27 (the system draws the menu bar; a
  synthetic click on the `NSStatusBarButton` does nothing), and computer use can't target a debug
  build. Check the live panel by hand.
- Commit and push each finished step; commits use the GitHub noreply address (set in this repo).
  **All credit goes to the user: no `Co-Authored-By` trailers, no "Generated with" lines in PRs.**
- No third-party dependencies beyond KeyboardShortcuts without asking the user.

## App shell (M5)

- **Settings**: SwiftUI `Settings` scene, `TabView` panes (General, Calls, Apps, Shortcuts) with
  `.formStyle(.grouped)`; the last pane is remembered (`@AppStorage("settingsPane")`). From views:
  `@Environment(\.openSettings)` + `NSApp.activate()`. From AppKit (reopen): `AppWindows.openSettings()`
  presses the hidden app menu's ⌘, item (`showSettingsWindow:` no longer opens SwiftUI Settings).
- **Show in Menu Bar** (`@AppStorage("showInMenuBar")`) drives `MenuBarExtra(isInserted:)`.
  `applicationShouldHandleReopen` opens Settings, so a hidden icon is never a dead end.
- **Open at Login**: `SMAppService.mainApp` (`LoginItem`), with "Open System Settings" when macOS
  wants approval.
- **Onboarding**: `OnboardingWindow`, an AppKit window hosting `OnboardingView`, opened by the app
  delegate at launch while `hasCompletedOnboarding` is false (closing it in any way sets it). Not a
  SwiftUI `Window` scene: a menu bar extra's label doesn't run `.task` on macOS 27, so nothing could
  open it. Fixed size from the first step's `fittingSize` with `NSHostingView.sizingOptions = []`:
  letting SwiftUI size the window (`preferredContentSize`) loops on macOS 27 until AppKit throws
  ("needs another Update Constraints in Window pass"). Permission step: `AudioPermission.request()` starts an unmuted global tap with a silent
  IOProc (nothing anyone hears changes) to make macOS ask, then polls `AudioPermission.isGranted()`.
- **Shortcuts** (KeyboardShortcuts names in `Shortcuts.swift`): none set by default. Microphone and
  call mode toggle on key up; volume up/down of the frontmost app in 10 % steps on key down, capped at
  the app's own level. No volume HUD exists for one app: VoiceOver gets an announcement.
- **About**: standard About panel with the KeyboardShortcuts MIT notice as credits (`AppWindows`).
- **App icon**: `Resources/AppIcon.icon` (Icon Composer): indigo automatic gradient; "Tracks" (three
  translucent rounded bars) and "Knobs" (three white capsules) as glass layers; the first group in
  `icon.json` is in front. Preview: `"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/
  Contents/Executables/ictool" Mixpilot/Resources/AppIcon.icon --export-image --output-file out.png
  --platform macOS --rendition Default|Dark|TintedDark|ClearLight --width 512 --height 512 --scale 1`.

## Dependencies

**KeyboardShortcuts 3.1.0** (sindresorhus, MIT), commit 772133d, pinned with `exactVersion`.
Reviewed line by line before adding (Oct 2026): no network, no private API, no keystroke logging;
global hotkeys through Carbon `RegisterEventHotKey` (no Accessibility/Input Monitoring permission);
stores `KeyboardShortcuts_<name>` JSON in UserDefaults; the recorder is a real `NSSearchField`;
Release builds fine at our 14.4 target (it uses `isolated deinit`).
- Its strings come from its own bundle. The "Fix Dependency Localizations" build phase
  (`scripts/localize-dependencies.sh`, so the target has `ENABLE_USER_SCRIPT_SANDBOXING = NO`)
  replaces its German with `Localization/KeyboardShortcuts/de.lproj` (Apple's terms; the placeholder
  must fit the field's 126 pt text area: "Kurzbefehl festlegen") and deletes every other language, so
  the recorder never shows a language the rest of the app doesn't.
- The MIT notice must stay in the About credits (`AppWindows.acknowledgements`).
- To update: read the new release's source, bump `version` in `project.pbxproj`, resolve, compare its
  en.lproj keys with ours, check the placeholder width, build Release, test the recorder in German.
- Any other dependency needs the user's approval first.

## Website

`website/build.py` writes `website/public` (commit it): home, privacy, support in English (`/`) and
German (`/de/`), a 404, sitemap and robots. Apple product-page style: system font, large tight
headlines, light/dark from `prefers-color-scheme`, blue pill buttons, rounded tiles, the panel on a
soft gradient "wallpaper". No JavaScript, no cookies, no web fonts; `website/vercel.json` sets a
strict CSP and serves `public/`. The download is `public/download/Mixpilot.dmg` (written by the
release script). Screenshots come from `scripts/snapshots.sh` (copy `build/snapshots/panel-*` to
`website/assets/`). The user is in France: no German Impressum; French *mentions légales* for a
non-professional individual can list just the host (offered, not added). The GitHub repo is private
for now; its homepage points to the site.

**Deploy = push to `main`.** The Vercel project `mixpilot` (team "Ahmed Maaloul's projects") is
connected to the GitHub repo with **Root Directory `website`**; every push to `main` deploys
`website/public` to production (mixpilot.blitzraum.com, mixpilot-henna.vercel.app). Don't run
`vercel deploy` from `website/` (the root directory would apply twice). When the project was first
linked, its root was the repo root and a push deployed an empty site over the real one (404):
check the Root Directory if that ever happens again. DNS: the user adds `A mixpilot 76.76.21.21`
at Spaceship (Vercel's recommendation).

Snapshot rendering pitfalls (for pictures that look like a Mac in use):
- `cacheDisplay` draws controls inactive. `SnapshotRenderer` shows a borderless key window and
  captures it with `CGWindowListCreateImage` (own windows need no permission; the function is looked
  up with `dlsym`, debug builds only).
- A process started from a terminal is never activated; run it through `open` (the script does)
  and switch to `.regular` activation policy. Sliders also need
  `.environment(\.controlActiveState, .key)`. `NSSwitch` still draws its "on" state gray.
- The default blue accent is forced with `.tint(systemBlue)` and the `routedTint` environment value.

## Release

`scripts/release-mac.sh` (like Handpilot's): localize + package tests → archive → export
developer-id → hardened-runtime check → DMG → sign → notarize (`--keychain-profile handpilot`) →
staple → `spctl`. `--test` runs everything locally with the development certificate and no
notarization (verified). Bump `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `Config/Base.xcconfig`
first. Download: mixpilot.blitzraum.com (Vercel). Support: support@blitzraum.com.

## Milestones

1. ✅ List apps producing audio, live updating, in a native menu bar panel.
2. ✅ Per-app volume and mute with process taps, clean teardown.
3. ✅ Per-app output device, saved settings, device-change handling. (Boost above 100 % was built,
   then removed at the user's request.)
4. ✅ Call detection and automatic lowering, microphone section.
5. ✅ Shortcuts, launch at login, settings window, onboarding, full English and German, app icon,
   privacy manifest, release script.

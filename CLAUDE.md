# Mixpilot

A macOS menu bar app that sets the volume of each app separately, like the volume mixer on Windows.
Main use case: during a call, keep the call loud and everything else quiet. English and German,
following the system language. Distributed outside the App Store (Developer ID, notarized).
macOS 14.4 or newer. One dependency, approved by the user: KeyboardShortcuts (from M5).

## Layout

```
Mixpilot.xcodeproj           Open this. App target + local package reference.
Config/Base.xcconfig         Bundle ID base (app.mixpilot → app.mixpilot.mac), team, version.
Info.plist                   Partial plist (usage descriptions); the rest comes from build settings.
Mixpilot/                    App target (UI and wiring only), folder-synchronized group
  App/                       @main + AppDelegate, MixerModel (state for the UI), AppDirectory (names,
                             icons), PreviewData, SnapshotRenderer (debug: previews → PNG)
  MenuBar/                   MixerPanel (the window-style menu bar extra), AppRow, MenuBarIcon
  Resources/                 Localizable.xcstrings, InfoPlist.xcstrings, AppIcon.icon
MixpilotKit/                 Swift package, no UI
  Sources/MixpilotCore/      Pure logic, fully tested: AppGrouper, Linger, AppAudioSettings,
                             AppSettingsStore, OutputDevice (+ kind), TapPlanner (later: call detector)
  Sources/MixpilotRender/    C: the audio thread's code (MPRenderIOProc, gain ramp, gain capped at 1)
  Sources/MixpilotAudio/     Core Audio HAL: HAL helpers, ProcessMonitor, DeviceMonitor, Responsibility
                             (private SPI), AudioDevices, TapSession (+ Output), TapManager
  Tests/MixpilotCoreTests/   Swift Testing: grouping, linger, tap planning, settings storage, device kinds
  Tests/MixpilotRenderTests/ Swift Testing against the C kernel with synthetic buffers
Localization/                de.py (German table, source of truth) + localize.py (sync + fill + check)
scripts/                     build.sh, run.sh, snapshots.sh, debug-volume.swift (set an app's volume in
                             a debug build without the panel), release-mac.sh (M5)
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
  Processes without an owning app (daemons) are hidden. Mixpilot hides itself.
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
  `build/debug-volume com.apple.QuickTimePlayerX 0.3` (0…2, `mute`, `unmute`,
  `device <UID>`, `device system`). Device UIDs: `system_profiler SPAudioDataType` doesn't show them;
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
- No third-party dependencies beyond KeyboardShortcuts without asking the user.

## Release (M5)

Like Handpilot's `scripts/release-mac.sh`: archive → export developer-id → DMG → sign → notarize
(`--keychain-profile handpilot`) → staple → `spctl` check. Download: mixpilot.blitzraum.com
(Vercel). Support: support@blitzraum.com.

## Milestones

1. ✅ List apps producing audio, live updating, in a native menu bar panel.
2. ✅ Per-app volume and mute with process taps, clean teardown.
3. ✅ Per-app output device, saved settings, device-change handling. (Boost above 100 % was built,
   then removed at the user's request.)
4. Call detection and automatic lowering, microphone section.
5. Shortcuts, launch at login, settings window, onboarding, full English and German, app icon.

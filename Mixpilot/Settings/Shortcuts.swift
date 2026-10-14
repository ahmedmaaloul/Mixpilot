import KeyboardShortcuts

/// Mixpilot's global keyboard shortcuts. None is set by default: people pick their own in
/// Settings ▸ Shortcuts, so Mixpilot never takes a shortcut another app relies on.
extension KeyboardShortcuts.Name {
    static let toggleMicrophone = Self("toggleMicrophone")
    static let toggleCallMode = Self("toggleCallMode")
    static let raiseFrontmostApp = Self("raiseFrontmostApp")
    static let lowerFrontmostApp = Self("lowerFrontmostApp")
}

enum Shortcuts {
    /// One step of the volume shortcuts, like the volume keys.
    static let volumeStep = 0.1

    /// Connects the shortcuts to the model. Hotkeys use Carbon's `RegisterEventHotKey` (inside the
    /// package): no Accessibility or Input Monitoring permission needed.
    static func install(model: MixerModel) {
        KeyboardShortcuts.onKeyUp(for: .toggleMicrophone) { [weak model] in
            model?.toggleMicrophone()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleCallMode) { [weak model] in
            model?.toggleCallMode()
        }
        KeyboardShortcuts.onKeyDown(for: .raiseFrontmostApp) { [weak model] in
            model?.adjustFrontmostApp(by: volumeStep)
        }
        KeyboardShortcuts.onKeyDown(for: .lowerFrontmostApp) { [weak model] in
            model?.adjustFrontmostApp(by: -volumeStep)
        }
    }
}

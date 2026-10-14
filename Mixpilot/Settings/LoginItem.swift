import Observation
import os
import ServiceManagement

/// Open at Login, through the system's login items (`SMAppService`). macOS may ask the person to
/// allow it in System Settings ▸ General ▸ Login Items.
@Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status
    private let log = Logger(subsystem: "app.mixpilot.mac", category: "login-item")

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// Registered, but waiting for the person's approval in System Settings.
    var needsApproval: Bool {
        status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Login item change failed: \(String(describing: error), privacy: .public)")
        }
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

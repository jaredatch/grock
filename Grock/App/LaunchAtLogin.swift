import Foundation
import ServiceManagement

/// Login item via SMAppService (modern replacement for LaunchAgent hacks).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[Grock] Launch at login failed: \(error.localizedDescription)")
            return false
        }
    }
}

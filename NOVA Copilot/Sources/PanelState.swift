import Combine
import Foundation
import ServiceManagement

@MainActor
final class PanelState: ObservableObject {
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var launchLoginError: String?

    init() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = false
        }
    }

    func clearLaunchLoginError() { launchLoginError = nil }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            launchLoginError = "Launch at Login requires macOS 13 or later."
            return
        }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchLoginError = error.localizedDescription
        }
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import ServiceManagement

/// Register only once by default. A later opt-out in Anasing or System Settings stays off.
enum LoginLaunch {
    static var service:SMAppService { .mainApp }
    static var enabled:Bool { service.status == .enabled }
    static var stateName:String {
        switch service.status {
        case .enabled:return "enabled"
        case .requiresApproval:return "requires-approval"
        case .notRegistered:return "disabled"
        case .notFound:return "not-found"
        @unknown default:return "unknown"
        }
    }
    static func enable() throws { try service.register() }
    static func disable() throws { try service.unregister() }
    static func enableOnFirstLaunch() {
        let defaults=UserDefaults.standard
        guard !defaults.bool(forKey:"configuredLaunchAtLogin") else { return }
        do {
            if service.status == .notRegistered || service.status == .notFound { try enable() }
            defaults.set(true,forKey:"configuredLaunchAtLogin")
        } catch {
            // Retry is user initiated from the menu; never spam registration or override an opt-out.
            defaults.set(true,forKey:"configuredLaunchAtLogin")
            NSLog("Anasing login registration: %@",error.localizedDescription)
        }
    }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
extension AppDelegate:NSMenuDelegate {
    func menuWillOpen(_ menu:NSMenu) { refreshLoginMenu() }
    func refreshLoginMenu() {
        loginItem?.state=LoginLaunch.enabled ? .on:LoginLaunch.service.status == .requiresApproval ? .mixed:.off
        loginApprovalItem?.isHidden=LoginLaunch.service.status != .requiresApproval
    }
    @objc func toggleLoginLaunch() {
        do {
            if LoginLaunch.service.status == .enabled || LoginLaunch.service.status == .requiresApproval { try LoginLaunch.disable() }
            else { try LoginLaunch.enable() }
            UserDefaults.standard.set(true,forKey:"configuredLaunchAtLogin")
            refreshLoginMenu()
            if LoginLaunch.service.status == .requiresApproval { LoginLaunch.openSettings() }
        } catch { showError("Launch at login · التشغيل عند تسجيل الدخول\n"+error.localizedDescription) }
    }
    @objc func openLoginSettings() { LoginLaunch.openSettings() }
}

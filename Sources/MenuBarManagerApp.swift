import AppKit
import SwiftUI

@main
struct MenuBarManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var diagnosticPreferencesSuiteName: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_UI_TESTING"] == "1" {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        let preferencesClient = makePreferencesClient()
        let launchAtLoginClient = LaunchAtLoginClient()
        let store = MenuBarManagerStore(
            preferencesClient: preferencesClient,
            launchAtLoginClient: launchAtLoginClient
        )

        let controller = StatusBarController(store: store)
        statusBarController = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.stop()
        if let diagnosticPreferencesSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: diagnosticPreferencesSuiteName)
        }
    }

    private func makePreferencesClient() -> MenuBarPreferencesClient {
        guard let diagnosticSettings = diagnosticInitialSettings() else {
            return MenuBarPreferencesClient()
        }

        let suiteName = "MenuBarManager.Diagnostics.\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return MenuBarPreferencesClient()
        }

        diagnosticPreferencesSuiteName = suiteName
        let client = MenuBarPreferencesClient(defaults: defaults)
        client.saveSettings(diagnosticSettings)
        return client
    }

    private func diagnosticInitialSettings() -> MenuBarSettings? {
        let environment = ProcessInfo.processInfo.environment
        guard let rawRules = environment["MENUBAR_MANAGER_DIAGNOSTIC_ITEM_VISIBILITIES"],
              let data = rawRules.data(using: .utf8),
              let decodedRules = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }

        let rules = decodedRules.reduce(into: [String: MenuBarItemVisibility]()) { result, entry in
            guard let visibility = MenuBarItemVisibility(rawValue: entry.value) else {
                return
            }

            result[entry.key] = visibility
        }

        var settings = MenuBarSettings.defaults
        settings.itemVisibilities = rules

        if let rawCollapsed = environment["MENUBAR_MANAGER_DIAGNOSTIC_COLLAPSED"] {
            settings.isCollapsed = rawCollapsed == "1"
        }

        return settings
    }
}

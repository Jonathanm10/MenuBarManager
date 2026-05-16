import Foundation

struct MenuBarPreferencesClient {
    private let defaults: UserDefaults
    private let settingsKey = "MenuBarManager.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSettings() -> MenuBarSettings {
        guard let data = defaults.data(forKey: settingsKey) else {
            return .defaults
        }

        do {
            return try JSONDecoder().decode(MenuBarSettings.self, from: data).sanitizedForLaunch()
        } catch {
            return .defaults
        }
    }

    func saveSettings(_ settings: MenuBarSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        defaults.set(data, forKey: settingsKey)
    }
}

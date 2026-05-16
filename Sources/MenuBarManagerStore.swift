import ApplicationServices
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MenuBarManagerStore {
    private static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    private let preferencesClient: MenuBarPreferencesClient
    private let launchAtLoginClient: LaunchAtLoginClient
    @ObservationIgnored
    private var autoCollapseTask: Task<Void, Never>?

    var settings: MenuBarSettings
    var launchAtLoginEnabled: Bool
    var lastLaunchAtLoginError: String?
    var menuBarItems: [ManagedMenuBarItem] = []
    var itemSearchText = ""
    var itemActionStatus: String?
    var isMovingMenuBarItem = false
    var accessibilityLabelsAreEnabled = AXIsProcessTrusted()
    var screenCapturePreviewsAreEnabled = CGPreflightScreenCaptureAccess()
    @ObservationIgnored
    var onSettingsChanged: ((MenuBarSettings) -> Void)?
    @ObservationIgnored
    var onRefreshMenuBarItems: (() -> [ManagedMenuBarItem])?
    @ObservationIgnored
    var onMoveMenuBarItem: ((ManagedMenuBarItem, MenuBarItemVisibility) async -> Bool)?
    @ObservationIgnored
    var onPlaceMenuBarItem: ((ManagedMenuBarItem, ManagedMenuBarItem?, MenuBarItemSection) async -> Bool)?
    @ObservationIgnored
    var preflightScreenCaptureAccess: () -> Bool = { CGPreflightScreenCaptureAccess() }
    @ObservationIgnored
    var requestScreenCaptureAccess: () -> Bool = { CGRequestScreenCaptureAccess() }
    @ObservationIgnored
    var openSystemSettings: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    @ObservationIgnored
    var revealAppInFinder: () -> Void = {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    init(
        preferencesClient: MenuBarPreferencesClient,
        launchAtLoginClient: LaunchAtLoginClient
    ) {
        self.preferencesClient = preferencesClient
        self.launchAtLoginClient = launchAtLoginClient
        settings = preferencesClient.loadSettings()
        launchAtLoginEnabled = launchAtLoginClient.isEnabled
    }

    var isCollapsed: Bool {
        settings.isCollapsed
    }

    var targetHiddenSpan: CGFloat {
        CGFloat(MenuBarLayoutPolicy.targetHiddenSpan(for: settings))
    }

    var filteredMenuBarItems: [ManagedMenuBarItem] {
        let query = itemSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return menuBarItems
        }

        return menuBarItems.filter { item in
            item.displayName.localizedCaseInsensitiveContains(query)
                || item.detail.localizedCaseInsensitiveContains(query)
        }
    }

    var filteredVisibleMenuBarItems: [ManagedMenuBarItem] {
        filteredMenuBarItems(in: .visible)
    }

    var filteredHiddenMenuBarItems: [ManagedMenuBarItem] {
        filteredMenuBarItems(in: .hidden)
    }

    var filteredProtectedMenuBarItems: [ManagedMenuBarItem] {
        filteredMenuBarItems(in: .protected)
    }

    var visibleItemCount: Int {
        menuBarItems.filter { $0.section == .visible }.count
    }

    var hiddenItemCount: Int {
        menuBarItems.filter { $0.section == .hidden }.count
    }

    var protectedItemCount: Int {
        menuBarItems.filter { $0.section == .protected }.count
    }

    var alwaysVisibleItemCount: Int {
        settings.alwaysVisibleItemIDs.count
    }

    var savedVisibilityRuleCount: Int {
        settings.itemVisibilities.count + settings.alwaysVisibleItemIDs.count
    }

    func movableFilteredItems(in section: MenuBarItemSection) -> [ManagedMenuBarItem] {
        filteredMenuBarItems.filter { item in
            item.section == section && item.canBeHidden
        }
    }

    func filteredMenuBarItems(in section: MenuBarItemSection) -> [ManagedMenuBarItem] {
        filteredMenuBarItems.filter { $0.section == section }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = launchAtLoginClient.isEnabled
    }

    func refreshMenuBarItems() {
        accessibilityLabelsAreEnabled = AXIsProcessTrusted()
        screenCapturePreviewsAreEnabled = preflightScreenCaptureAccess()
        menuBarItems = onRefreshMenuBarItems?() ?? []
    }

    func requestAccessibilityLabels() {
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary

        accessibilityLabelsAreEnabled = AXIsProcessTrustedWithOptions(options)
        itemActionStatus = accessibilityLabelsAreEnabled
            ? "Accessibility labels enabled."
            : "Grant Accessibility access, then refresh."
    }

    func requestScreenCapturePreviews() {
        let requestGranted = requestScreenCaptureAccess()
        screenCapturePreviewsAreEnabled = requestGranted || preflightScreenCaptureAccess()

        if !screenCapturePreviewsAreEnabled {
            _ = openSystemSettings(Self.screenRecordingSettingsURL)
            revealAppInFinder()
        }

        itemActionStatus = screenCapturePreviewsAreEnabled
            ? "Menu bar previews enabled."
            : "Screen Recording settings opened. Grant access, then restart the app."
    }

    func toggleCollapsed() {
        updateSettings { settings in
            settings.isCollapsed.toggle()
        }

        if !settings.isCollapsed {
            scheduleAutoCollapseIfNeeded()
        }
    }

    func setCollapsed(_ isCollapsed: Bool) {
        updateSettings { settings in
            settings.isCollapsed = isCollapsed
        }

        if !isCollapsed {
            scheduleAutoCollapseIfNeeded()
        }
    }

    func setHiddenWidth(_ hiddenWidth: Double) {
        updateSettings { settings in
            settings.hiddenWidth = MenuBarLayoutPolicy.clampedHiddenWidth(hiddenWidth)
        }
    }

    func setAutoCollapseEnabled(_ isEnabled: Bool) {
        updateSettings { settings in
            settings.autoCollapseEnabled = isEnabled
        }

        if isEnabled, !settings.isCollapsed {
            scheduleAutoCollapseIfNeeded()
        } else {
            autoCollapseTask?.cancel()
        }
    }

    func setAutoCollapseDelay(_ delay: Double) {
        updateSettings { settings in
            settings.autoCollapseDelay = delay.rounded()
        }

        if settings.autoCollapseEnabled, !settings.isCollapsed {
            scheduleAutoCollapseIfNeeded()
        }
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try launchAtLoginClient.setEnabled(isEnabled)
            launchAtLoginEnabled = launchAtLoginClient.isEnabled
            lastLaunchAtLoginError = nil
        } catch {
            launchAtLoginEnabled = launchAtLoginClient.isEnabled
            lastLaunchAtLoginError = error.localizedDescription
        }
    }

    func setKeepOnlySelectedVisibleEnabled(_ isEnabled: Bool) {
        updateSettings { settings in
            settings.visibilityPolicyMode = isEnabled ? .keepOnlySelectedVisible : .manual

            if isEnabled, settings.alwaysVisibleItemIDs.isEmpty {
                settings.alwaysVisibleItemIDs = Set(
                    menuBarItems
                        .filter { $0.section == .visible && $0.canBeHidden }
                        .map(\.stableID)
                )
            }
        }

        itemActionStatus = isEnabled
            ? "\(settings.alwaysVisibleItemIDs.count) item(s) selected to stay visible."
            : "Manual visibility rules enabled."
    }

    func enableKeepOnlySelectedVisibleIfNeeded() {
        guard settings.visibilityPolicyMode != .keepOnlySelectedVisible else {
            return
        }

        setKeepOnlySelectedVisibleEnabled(true)
    }

    func isAlwaysVisible(_ item: ManagedMenuBarItem) -> Bool {
        settings.alwaysVisibleItemIDs.contains(item.stableID)
    }

    func setMenuBarItemAlwaysVisible(_ item: ManagedMenuBarItem, isAlwaysVisible: Bool) {
        guard item.canBeHidden else {
            return
        }

        moveMenuBarItem(item, to: isAlwaysVisible ? .visible : .hidden)
    }

    func moveMenuBarItem(_ item: ManagedMenuBarItem, to visibility: MenuBarItemVisibility) {
        guard !isMovingMenuBarItem else {
            return
        }

        isMovingMenuBarItem = true
        itemActionStatus = visibility == .hidden
            ? "Hiding \(item.displayName)..."
            : "Showing \(item.displayName)..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let succeeded = await onMoveMenuBarItem?(item, visibility) ?? false
            isMovingMenuBarItem = false

            if succeeded {
                updateSettings { settings in
                    recordVisibilityChoice(item.stableID, visibility, in: &settings)
                }
                refreshMenuBarItems()
                itemActionStatus = visibility == .hidden
                    ? "\(item.displayName) is hidden."
                    : "\(item.displayName) is visible."
            } else {
                refreshMenuBarItems()
                itemActionStatus = "Could not move \(item.displayName)."
            }
        }
    }

    func placeMenuBarItem(
        withID itemID: String,
        before targetID: String?,
        in section: MenuBarItemSection
    ) {
        guard !isMovingMenuBarItem else {
            return
        }
        guard section != .protected else {
            itemActionStatus = "Pinned items cannot be rearranged."
            return
        }
        guard let item = menuBarItems.first(where: { $0.id == itemID }) else {
            itemActionStatus = "Menu bar item was not found. Refresh and try again."
            return
        }
        guard item.canBeHidden else {
            itemActionStatus = "\(item.displayName) is pinned by macOS."
            return
        }

        let target = targetID.flatMap { id in
            menuBarItems.first { $0.id == id }
        }

        if target?.id == item.id {
            return
        }

        placeMenuBarItem(item, before: target, in: section)
    }

    func placeMenuBarItem(
        _ item: ManagedMenuBarItem,
        before target: ManagedMenuBarItem?,
        in section: MenuBarItemSection
    ) {
        guard !isMovingMenuBarItem else {
            return
        }
        guard section != .protected, item.canBeHidden else {
            itemActionStatus = item.canBeHidden
                ? "Pinned items cannot be rearranged."
                : "\(item.displayName) is pinned by macOS."
            return
        }

        let visibility: MenuBarItemVisibility = section == .visible ? .visible : .hidden
        isMovingMenuBarItem = true
        if let target {
            itemActionStatus = "Moving \(item.displayName) before \(target.displayName)..."
        } else {
            itemActionStatus = visibility == .hidden
                ? "Moving \(item.displayName) to Hidden..."
                : "Moving \(item.displayName) to Shown..."
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let succeeded: Bool
            if let onPlaceMenuBarItem {
                succeeded = await onPlaceMenuBarItem(item, target, section)
            } else {
                succeeded = await onMoveMenuBarItem?(item, visibility) ?? false
            }

            isMovingMenuBarItem = false

            if succeeded {
                updateSettings { settings in
                    recordVisibilityChoice(item.stableID, visibility, in: &settings)
                }
                refreshMenuBarItems()
                itemActionStatus = target == nil
                    ? "\(item.displayName) moved to \(section.displayTitle)."
                    : "\(item.displayName) reordered in \(section.displayTitle)."
            } else {
                refreshMenuBarItems()
                itemActionStatus = "Could not move \(item.displayName)."
            }
        }
    }

    func moveFilteredMenuBarItems(in section: MenuBarItemSection, to visibility: MenuBarItemVisibility) {
        guard !isMovingMenuBarItem else {
            return
        }

        let itemsToMove = movableFilteredItems(in: section)
        guard !itemsToMove.isEmpty else {
            itemActionStatus = "No matching items to move."
            return
        }

        isMovingMenuBarItem = true
        itemActionStatus = visibility == .hidden
            ? "Hiding \(itemsToMove.count) item(s)..."
            : "Showing \(itemsToMove.count) item(s)..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            var succeededItems: [ManagedMenuBarItem] = []
            for item in itemsToMove {
                guard await onMoveMenuBarItem?(item, visibility) == true else {
                    continue
                }

                succeededItems.append(item)
            }

            if !succeededItems.isEmpty {
                updateSettings { settings in
                    for item in succeededItems {
                        recordVisibilityChoice(item.stableID, visibility, in: &settings)
                    }
                }
            }

            isMovingMenuBarItem = false
            refreshMenuBarItems()
            itemActionStatus = "\(succeededItems.count) of \(itemsToMove.count) item(s) moved."
        }
    }

    func clearSavedItemVisibilityRules() {
        guard savedVisibilityRuleCount > 0 else {
            itemActionStatus = "No saved visibility rules."
            return
        }

        updateSettings { settings in
            settings.visibilityPolicyMode = .manual
            settings.itemVisibilities = [:]
            settings.alwaysVisibleItemIDs = []
        }
        refreshMenuBarItems()
        itemActionStatus = "Saved visibility rules cleared."
    }

    private func recordVisibilityChoice(
        _ stableID: String,
        _ visibility: MenuBarItemVisibility,
        in settings: inout MenuBarSettings
    ) {
        switch settings.visibilityPolicyMode {
        case .manual:
            settings.itemVisibilities[stableID] = visibility
        case .keepOnlySelectedVisible:
            settings.itemVisibilities.removeValue(forKey: stableID)
            switch visibility {
            case .visible:
                settings.alwaysVisibleItemIDs.insert(stableID)
            case .hidden:
                settings.alwaysVisibleItemIDs.remove(stableID)
            }
        }
    }

    private func updateSettings(_ update: (inout MenuBarSettings) -> Void) {
        autoCollapseTask?.cancel()
        update(&settings)
        preferencesClient.saveSettings(settings)
        onSettingsChanged?(settings)
    }

    private func scheduleAutoCollapseIfNeeded() {
        autoCollapseTask?.cancel()

        guard settings.autoCollapseEnabled else {
            return
        }

        let delay = max(1, settings.autoCollapseDelay)
        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else {
                return
            }

            self?.setCollapsed(true)
        }
    }
}

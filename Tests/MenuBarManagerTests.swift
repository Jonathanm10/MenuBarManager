import CoreGraphics
import XCTest

final class MenuBarManagerTests: XCTestCase {
    func testDefaultsStartCollapsedWithHiddenSpan() {
        let settings = MenuBarSettings.defaults

        XCTAssertTrue(settings.isCollapsed)
        XCTAssertEqual(settings.hiddenWidth, 1_100)
        XCTAssertEqual(
            MenuBarLayoutPolicy.targetHiddenSpan(for: settings),
            1_100
        )
    }

    func testLaunchSanitizationPreservesCollapsedState() {
        let persisted = MenuBarSettings(
            isCollapsed: true,
            hiddenWidth: 2_000,
            autoCollapseEnabled: true,
            autoCollapseDelay: 99
        )

        let sanitized = persisted.sanitizedForLaunch()

        XCTAssertTrue(sanitized.isCollapsed)
        XCTAssertEqual(sanitized.hiddenWidth, MenuBarLayoutPolicy.maxHiddenWidth)
        XCTAssertEqual(sanitized.autoCollapseDelay, 30)
    }

    func testLaunchSanitizationDropsLegacyOpaqueMenuBarRules() {
        let persisted = MenuBarSettings(
            isCollapsed: true,
            hiddenWidth: 1_100,
            autoCollapseEnabled: true,
            autoCollapseDelay: 6,
            alwaysVisibleItemIDs: [
                "com.apple.controlcenter::Control Center#window-10-w38",
                "com.apple.controlcenter:Item-0:Control Center#window-11-w38",
                "com.apple.controlcenter:bb3cc23c-6950-4e96-8b40-850e09f46934:Control Center",
            ],
            itemVisibilities: [
                "com.apple.controlcenter:Amphetamine:Control Center": .visible,
                "com.apple.controlcenter:Item-0:Control Center#window-12-w38": .hidden,
                "com.apple.controlcenter:bb3cc23c-6950-4e96-8b40-850e09f46934:Control Center": .hidden,
            ]
        )

        let sanitized = persisted.sanitizedForLaunch()

        XCTAssertEqual(
            sanitized.alwaysVisibleItemIDs,
            ["com.apple.controlcenter::Control Center#window-10-w38"]
        )
        XCTAssertEqual(
            sanitized.itemVisibilities,
            ["com.apple.controlcenter:Amphetamine:Control Center": .visible]
        )
    }

    func testSelectedOnlyPolicyTargetsUnselectedItemsAsHidden() {
        let settings = MenuBarSettings(
            isCollapsed: true,
            hiddenWidth: 1_100,
            autoCollapseEnabled: true,
            autoCollapseDelay: 6,
            visibilityPolicyMode: .keepOnlySelectedVisible,
            alwaysVisibleItemIDs: ["alpha"]
        )

        XCTAssertEqual(settings.preferredVisibility(for: "alpha"), .visible)
        XCTAssertEqual(settings.preferredVisibility(for: "beta"), .hidden)
    }

    func testSelectedOnlyPolicyWithoutSelectedItemsDoesNotHideEverything() {
        let settings = MenuBarSettings(
            isCollapsed: true,
            hiddenWidth: 1_100,
            autoCollapseEnabled: true,
            autoCollapseDelay: 6,
            visibilityPolicyMode: .keepOnlySelectedVisible,
            alwaysVisibleItemIDs: []
        )

        XCTAssertNil(settings.preferredVisibility(for: "alpha"))
        XCTAssertNil(settings.preferredVisibility(for: "beta"))
    }

    func testCollapsedLengthIsClampedAndKeepsControlReachable() {
        let settings = MenuBarSettings(
            isCollapsed: true,
            hiddenWidth: 2_000,
            autoCollapseEnabled: true,
            autoCollapseDelay: 6
        )

        XCTAssertEqual(
            MenuBarLayoutPolicy.targetHiddenSpan(for: settings),
            MenuBarLayoutPolicy.maxHiddenWidth
        )
    }

    func testPreferencesClientSanitizesPersistedDangerousState() throws {
        let suiteName = "MenuBarManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let dangerousSettings = MenuBarSettings(
            isCollapsed: true,
            hiddenWidth: 2_000,
            autoCollapseEnabled: true,
            autoCollapseDelay: 999
        )
        let data = try JSONEncoder().encode(dangerousSettings)
        defaults.set(data, forKey: "MenuBarManager.settings")

        let client = MenuBarPreferencesClient(defaults: defaults)
        let loaded = client.loadSettings()

        XCTAssertTrue(loaded.isCollapsed)
        XCTAssertEqual(loaded.hiddenWidth, MenuBarLayoutPolicy.maxHiddenWidth)
        XCTAssertEqual(loaded.autoCollapseDelay, 30)
    }

    func testDuplicateMenuBarItemIdentitiesAreDisambiguatedForPersistence() {
        let first = snapshot(windowID: 10, x: 900, width: 38)
        let second = snapshot(windowID: 11, x: 940, width: 38)
        let identities = MenuBarItemIdentityResolver.resolve(
            items: [second, first],
            stableIDForItem: { _ in "com.apple.controlcenter:Item-0:Control Center" },
            displayNameForItem: { _ in "Control Center" }
        )

        XCTAssertEqual(identities[10]?.displayName, "Control Center #1")
        XCTAssertEqual(identities[11]?.displayName, "Control Center #2")
        XCTAssertNotEqual(identities[10]?.stableID, identities[11]?.stableID)
        XCTAssertEqual(
            identities[10]?.stableID,
            "com.apple.controlcenter:Item-0:Control Center#window-10-w38"
        )
    }

    func testDuplicateMenuBarItemIdentityPreservesRuntimeMappingAfterMove() {
        let movedOffscreen = snapshot(windowID: 10, x: -4_000, width: 38)
        let stillVisible = snapshot(windowID: 11, x: 940, width: 38)
        let identities = MenuBarItemIdentityResolver.resolve(
            items: [movedOffscreen, stillVisible],
            existingStableIDsByWindowID: [
                10: "com.apple.controlcenter:Item-0:Control Center#window-10-w38",
                11: "com.apple.controlcenter:Item-0:Control Center#window-11-w38",
            ],
            stableIDForItem: { _ in "com.apple.controlcenter:Item-0:Control Center" },
            displayNameForItem: { _ in "Control Center" }
        )

        XCTAssertEqual(
            identities[10]?.stableID,
            "com.apple.controlcenter:Item-0:Control Center#window-10-w38"
        )
        XCTAssertEqual(
            identities[11]?.stableID,
            "com.apple.controlcenter:Item-0:Control Center#window-11-w38"
        )
    }

    func testMenuBarItemIdentityPreservesExistingRuntimeMappingForSingleItem() {
        let item = snapshot(windowID: 10, x: 900, width: 38)
        let identities = MenuBarItemIdentityResolver.resolve(
            items: [item],
            existingStableIDsByWindowID: [
                10: "previously-resolved-id",
            ],
            stableIDForItem: { _ in "newly-resolved-id" },
            displayNameForItem: { _ in "Control Center" }
        )

        XCTAssertEqual(identities[10]?.stableID, "previously-resolved-id")
        XCTAssertEqual(identities[10]?.displayName, "Control Center")
    }

    func testOpaqueControlCenterTitleIsNotShownAsUserFacingName() {
        let item = snapshot(
            windowID: 12,
            x: 900,
            width: 38,
            title: "bb3cc23c-6950-4e96-8b40-850e09f46934"
        )

        XCTAssertEqual(item.displayName, RealMenuBarItemSnapshot.unlabeledMenuBarItemDisplayName)
        XCTAssertEqual(item.detail, "com.apple.controlcenter")
        XCTAssertEqual(item.stableID, "com.apple.controlcenter::Control Center")
    }

    func testAccessibilityDescriptionCanReplaceOpaqueMenuBarTitle() {
        let item = snapshot(
            windowID: 12,
            x: 900,
            width: 38,
            title: "Item-0",
            accessibilityTitle: "KeyboardBrightness"
        )

        XCTAssertEqual(item.displayName, "Keyboard Brightness")
        XCTAssertEqual(item.detail, "com.apple.controlcenter")
        XCTAssertEqual(item.stableID, "com.apple.controlcenter:KeyboardBrightness:Control Center")
    }

    func testCamelCaseIconTitleIsHumanizedAsAppName() {
        let item = snapshot(
            windowID: 12,
            x: 900,
            width: 38,
            title: "raycastIcon"
        )

        XCTAssertEqual(item.displayName, "Raycast")
        XCTAssertEqual(item.detail, "com.apple.controlcenter")
    }

    @MainActor
    func testRequestScreenCapturePreviewsOpensPrivacySettingsWhenAccessStillMissing() throws {
        let store = try makeStore()
        var requestWasMade = false
        var openedURL: URL?
        var appWasRevealed = false
        store.requestScreenCaptureAccess = {
            requestWasMade = true
            return false
        }
        store.preflightScreenCaptureAccess = { false }
        store.openSystemSettings = { url in
            openedURL = url
            return true
        }
        store.revealAppInFinder = {
            appWasRevealed = true
        }

        store.requestScreenCapturePreviews()

        XCTAssertTrue(requestWasMade)
        XCTAssertTrue(appWasRevealed)
        XCTAssertFalse(store.screenCapturePreviewsAreEnabled)
        XCTAssertEqual(
            openedURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
        XCTAssertEqual(
            store.itemActionStatus,
            "Screen Recording settings opened. Grant access, then restart the app."
        )
    }

    @MainActor
    func testRequestScreenCapturePreviewsDoesNotOpenPrivacySettingsWhenGranted() throws {
        let store = try makeStore()
        var openedSettings = false
        var appWasRevealed = false
        store.requestScreenCaptureAccess = { true }
        store.preflightScreenCaptureAccess = { false }
        store.openSystemSettings = { _ in
            openedSettings = true
            return true
        }
        store.revealAppInFinder = {
            appWasRevealed = true
        }

        store.requestScreenCapturePreviews()

        XCTAssertTrue(store.screenCapturePreviewsAreEnabled)
        XCTAssertFalse(openedSettings)
        XCTAssertFalse(appWasRevealed)
        XCTAssertEqual(store.itemActionStatus, "Menu bar previews enabled.")
    }

    @MainActor
    func testBulkMoveFilteredVisibleItemsPersistsSuccessfulRules() async throws {
        let store = try makeStore()
        let visibleItem = managedItem(stableID: "visible-item", section: .visible)
        let hiddenItem = managedItem(stableID: "hidden-item", section: .hidden)
        store.menuBarItems = [visibleItem, hiddenItem]

        var movedStableIDs: [String] = []
        store.onMoveMenuBarItem = { item, visibility in
            XCTAssertEqual(visibility, .hidden)
            movedStableIDs.append(item.stableID)
            return true
        }

        store.moveFilteredMenuBarItems(in: .visible, to: .hidden)
        await waitUntilIdle(store)

        XCTAssertEqual(movedStableIDs, ["visible-item"])
        XCTAssertEqual(store.settings.itemVisibilities, ["visible-item": .hidden])
        XCTAssertEqual(store.itemActionStatus, "1 of 1 item(s) moved.")
    }

    @MainActor
    func testBulkMoveHonorsSearchFilterAndSkipsPinnedItems() async throws {
        let store = try makeStore()
        store.menuBarItems = [
            managedItem(stableID: "alpha", displayName: "Alpha", section: .visible),
            managedItem(stableID: "beta", displayName: "Beta", section: .visible),
            managedItem(stableID: "clock", displayName: "Clock", section: .protected, canBeHidden: false),
        ]
        store.itemSearchText = "alp"

        var movedStableIDs: [String] = []
        store.onMoveMenuBarItem = { item, _ in
            movedStableIDs.append(item.stableID)
            return true
        }

        store.moveFilteredMenuBarItems(in: .visible, to: .hidden)
        await waitUntilIdle(store)

        XCTAssertEqual(movedStableIDs, ["alpha"])
        XCTAssertEqual(store.settings.itemVisibilities, ["alpha": .hidden])
    }

    @MainActor
    func testClearSavedVisibilityRulesPersistsEmptyRules() throws {
        let store = try makeStore(
            settings: MenuBarSettings(
                isCollapsed: true,
                hiddenWidth: 1_100,
                autoCollapseEnabled: true,
                autoCollapseDelay: 6,
                itemVisibilities: ["alpha": .hidden]
            )
        )

        store.clearSavedItemVisibilityRules()

        XCTAssertTrue(store.settings.itemVisibilities.isEmpty)
        XCTAssertEqual(store.itemActionStatus, "Saved visibility rules cleared.")
    }

    @MainActor
    func testClearSavedVisibilityRulesDisablesSelectedOnlyPolicy() throws {
        let store = try makeStore(
            settings: MenuBarSettings(
                isCollapsed: true,
                hiddenWidth: 1_100,
                autoCollapseEnabled: true,
                autoCollapseDelay: 6,
                visibilityPolicyMode: .keepOnlySelectedVisible,
                alwaysVisibleItemIDs: ["alpha"]
            )
        )

        store.clearSavedItemVisibilityRules()

        XCTAssertEqual(store.settings.visibilityPolicyMode, .manual)
        XCTAssertTrue(store.settings.alwaysVisibleItemIDs.isEmpty)
        XCTAssertTrue(store.settings.itemVisibilities.isEmpty)
        XCTAssertNil(store.settings.preferredVisibility(for: "beta"))
    }

    @MainActor
    func testEnablingSelectedOnlyPolicySeedsCurrentVisibleItems() throws {
        let store = try makeStore()
        store.menuBarItems = [
            managedItem(stableID: "alpha", section: .visible),
            managedItem(stableID: "beta", section: .hidden),
            managedItem(stableID: "clock", section: .protected, canBeHidden: false),
        ]

        store.setKeepOnlySelectedVisibleEnabled(true)

        XCTAssertEqual(store.settings.visibilityPolicyMode, .keepOnlySelectedVisible)
        XCTAssertEqual(store.settings.alwaysVisibleItemIDs, ["alpha"])
        XCTAssertEqual(store.itemActionStatus, "1 item(s) selected to stay visible.")
    }

    @MainActor
    func testSelectedOnlyPolicyShowingItemAddsItToAlwaysVisibleRules() async throws {
        let store = try makeStore(
            settings: MenuBarSettings(
                isCollapsed: true,
                hiddenWidth: 1_100,
                autoCollapseEnabled: true,
                autoCollapseDelay: 6,
                visibilityPolicyMode: .keepOnlySelectedVisible,
                alwaysVisibleItemIDs: ["alpha"]
            )
        )
        let hiddenItem = managedItem(stableID: "beta", section: .hidden)

        store.onMoveMenuBarItem = { item, visibility in
            XCTAssertEqual(item.stableID, "beta")
            XCTAssertEqual(visibility, .visible)
            return true
        }

        store.setMenuBarItemAlwaysVisible(hiddenItem, isAlwaysVisible: true)
        await waitUntilIdle(store)

        XCTAssertEqual(store.settings.alwaysVisibleItemIDs, ["alpha", "beta"])
        XCTAssertTrue(store.settings.itemVisibilities.isEmpty)
    }

    @MainActor
    func testSelectedOnlyPolicyHidingItemRemovesItFromAlwaysVisibleRules() async throws {
        let store = try makeStore(
            settings: MenuBarSettings(
                isCollapsed: true,
                hiddenWidth: 1_100,
                autoCollapseEnabled: true,
                autoCollapseDelay: 6,
                visibilityPolicyMode: .keepOnlySelectedVisible,
                alwaysVisibleItemIDs: ["alpha", "beta"]
            )
        )
        let visibleItem = managedItem(stableID: "beta", section: .visible)

        store.onMoveMenuBarItem = { item, visibility in
            XCTAssertEqual(item.stableID, "beta")
            XCTAssertEqual(visibility, .hidden)
            return true
        }

        store.setMenuBarItemAlwaysVisible(visibleItem, isAlwaysVisible: false)
        await waitUntilIdle(store)

        XCTAssertEqual(store.settings.alwaysVisibleItemIDs, ["alpha"])
        XCTAssertTrue(store.settings.itemVisibilities.isEmpty)
    }

    @MainActor
    func testPlaceMenuBarItemPersistsDroppedSectionRule() async throws {
        let store = try makeStore()
        let item = managedItem(stableID: "alpha", section: .visible)
        let target = managedItem(stableID: "beta", section: .hidden)
        store.menuBarItems = [item, target]

        var placedItemID: String?
        var placedTargetID: String?
        var placedSection: MenuBarItemSection?
        store.onPlaceMenuBarItem = { item, target, section in
            placedItemID = item.stableID
            placedTargetID = target?.stableID
            placedSection = section
            return true
        }

        store.placeMenuBarItem(withID: item.id, before: target.id, in: .hidden)
        await waitUntilIdle(store)

        XCTAssertEqual(placedItemID, "alpha")
        XCTAssertEqual(placedTargetID, "beta")
        XCTAssertEqual(placedSection, .hidden)
        XCTAssertEqual(store.settings.itemVisibilities, ["alpha": .hidden])
        XCTAssertEqual(store.itemActionStatus, "alpha reordered in Hidden.")
    }

    @MainActor
    private func makeStore(settings: MenuBarSettings = .defaults) throws -> MenuBarManagerStore {
        let suiteName = "MenuBarManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = MenuBarPreferencesClient(defaults: defaults)
        preferences.saveSettings(settings)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        return MenuBarManagerStore(
            preferencesClient: preferences,
            launchAtLoginClient: LaunchAtLoginClient()
        )
    }

    private func managedItem(
        stableID: String,
        displayName: String? = nil,
        section: MenuBarItemSection,
        canBeHidden: Bool = true
    ) -> ManagedMenuBarItem {
        ManagedMenuBarItem(
            id: "\(stableID)-runtime",
            stableID: stableID,
            displayName: displayName ?? stableID,
            detail: "test item",
            sortX: 0,
            icon: nil,
            section: section,
            preferredVisibility: nil,
            canBeHidden: canBeHidden
        )
    }

    @MainActor
    private func waitUntilIdle(
        _ store: MenuBarManagerStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 {
            if !store.isMovingMenuBarItem {
                return
            }

            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTFail(
            "Timed out waiting for store to become idle. status=\(store.itemActionStatus ?? "nil")",
            file: file,
            line: line
        )
    }

    private func snapshot(
        windowID: CGWindowID,
        x: Double,
        width: Double,
        title: String = "Item-0",
        accessibilityTitle: String? = nil
    ) -> RealMenuBarItemSnapshot {
        RealMenuBarItemSnapshot(
            windowID: windowID,
            frame: CGRect(x: x, y: 0, width: width, height: 33),
            title: title,
            ownerPID: 100,
            ownerName: "Control Center",
            bundleIdentifier: "com.apple.controlcenter",
            accessibilityTitle: accessibilityTitle,
            layer: Int(kCGStatusWindowLevel),
            alpha: 1,
            isOnScreen: x >= 0,
            isCurrentApp: false
        )
    }
}

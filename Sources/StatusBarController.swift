import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let store: MenuBarManagerStore
    private let configurationWindowSize = NSSize(width: 860, height: 720)
    private var configurationWindow: NSPanel?
    private var hiddenDividerItem: NSStatusItem?
    private var controlItem: NSStatusItem?
    private var diagnosticProbeItem: NSStatusItem?
    private let diagnosticProbeIdentifier = ProcessInfo.processInfo.environment["MENUBAR_MANAGER_DIAGNOSTIC_PROBE_ID"]
        ?? "MenuBarManagerDiagnosticProbe.v1"
    private let hiddenDividerIdentifier = ProcessInfo.processInfo.environment["MENUBAR_MANAGER_DIAGNOSTIC_DIVIDER_ID"]
        ?? "MenuBarManagerHiddenDivider.v4"
    private var diagnosticExpandedProbeFrame: CGRect?
    private var diagnosticExpandedProbeWindowID: CGWindowID?
    private var diagnosticExpandedProbeWasInsideScreen = false
    private var privateMoveDiagnostics: [String: Any] = [:]
    private var privatelyMovedWindowIDs: [CGWindowID] = []
    private var hiddenMenuBarWindowIDs: Set<CGWindowID> = []
    private var menuBarSyncTask: Task<Void, Never>?
    private var menuBarSyncDiagnostics: [String: Any] = [:]
    private var diagnosticExpandedRealMenuBarItemCount = 0
    private var diagnosticExpandedVisibleRealMenuBarItemCount = 0
    private var diagnosticExpandedControlFrame: CGRect?
    private var diagnosticExpandedDividerFrame: CGRect?
    private var menuBarIconCache: [CGWindowID: NSImage] = [:]
    private var pendingMenuBarIconCaptures: Set<CGWindowID> = []
    private var managedStableIDsByWindowID: [CGWindowID: String] = [:]

    init(store: MenuBarManagerStore) {
        self.store = store
        super.init()
    }

    private var controlStatusView: NSView? {
        controlItem?.button
    }

    func start() {
        NSApp.applicationIconImage = Self.makeStatusBarIcon()
        createStatusItems()
        configureConfigurationWindow()
        configureItemManagement()
        applySettings(store.settings)
        scheduleDiagnosticsIfNeeded()
        scheduleRevealIfNeeded()

        store.onSettingsChanged = { [weak self] settings in
            Task { @MainActor in
                self?.applySettings(settings)
            }
        }
    }

    func stop() {
        if let diagnosticProbeItem {
            NSStatusBar.system.removeStatusItem(diagnosticProbeItem)
        }

        if let controlItem {
            NSStatusBar.system.removeStatusItem(controlItem)
        }
        if let hiddenDividerItem {
            NSStatusBar.system.removeStatusItem(hiddenDividerItem)
        }

        configurationWindow?.orderOut(nil)
        menuBarSyncTask?.cancel()
    }

    private func createStatusItems() {
        let controlItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        controlItem.behavior = []

        if let button = controlItem.button {
            let image = Self.makeStatusBarIcon()
            button.image = image
            button.cell?.image = image
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.isBordered = false
            button.setAccessibilityLabel("MenuBarManager")
            button.setAccessibilityIdentifier("MenuBarManagerStatusButton")
            button.target = self
            button.action = #selector(controlButtonPressed(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "MenuBarManager"
        }

        self.controlItem = controlItem

        let hiddenDividerItem = NSStatusBar.system.statusItem(withLength: 1)
        hiddenDividerItem.autosaveName = hiddenDividerIdentifier
        hiddenDividerItem.behavior = []

        if let button = hiddenDividerItem.button {
            button.title = ""
            button.image = nil
            button.isBordered = false
            button.cell?.isEnabled = false
            button.setAccessibilityLabel("MenuBarManagerHiddenDivider")
            button.setAccessibilityIdentifier("MenuBarManagerHiddenDivider")
            button.toolTip = nil
        }

        self.hiddenDividerItem = hiddenDividerItem

        if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_DIAGNOSTIC_PROBE_ITEM"] == "1" {
            let diagnosticProbeItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            diagnosticProbeItem.autosaveName = diagnosticProbeIdentifier
            diagnosticProbeItem.behavior = [.removalAllowed, .terminationOnRemoval]

            if let button = diagnosticProbeItem.button {
                button.title = "T"
                button.font = .systemFont(ofSize: 11, weight: .semibold)
                button.toolTip = "MenuBarManager diagnostic probe"
                button.setAccessibilityLabel("MenuBarManagerDiagnosticProbe")
                button.setAccessibilityIdentifier("MenuBarManagerDiagnosticProbe")
            }

            self.diagnosticProbeItem = diagnosticProbeItem
        }
    }

    private static func makeStatusBarIcon() -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let dotDiameter = 3.8
            let spacing = 4.3
            let totalWidth = dotDiameter * 3 + spacing * 2
            let startX = rect.midX - totalWidth / 2
            let y = rect.midY - dotDiameter / 2

            NSColor.white.setFill()
            for index in 0..<3 {
                let x = startX + CGFloat(index) * (dotDiameter + spacing)
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotDiameter, height: dotDiameter)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func previewStatusBarIcon() -> NSImage {
        makeStatusBarIcon()
    }

    private func configureConfigurationWindow() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: configurationWindowSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "MenuBarManager"
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true
        panel.setAccessibilityLabel("MenuBarManagerSettingsWindow")
        panel.setAccessibilityIdentifier("MenuBarManagerSettingsWindow")
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: MenuBarConfigurationView(store: store))

        self.configurationWindow = panel
    }

    @objc
    private func controlButtonPressed(_ sender: NSStatusBarButton) {
        controlStatusViewMouseUp(with: NSApp.currentEvent)
    }

    fileprivate func controlStatusViewMouseUp(with event: NSEvent?) {
        if event?.type == .rightMouseUp {
            if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_APPLY_DIAGNOSTIC_VISIBILITY_RULES"] != "1" {
                showControlMenu()
            }
            return
        }

        store.toggleCollapsed()
    }

    private func showControlMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsFromMenu(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit MenuBarManager",
            action: #selector(quitFromMenu(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        controlItem?.button?.highlight(true)
        menu.delegate = self
        if let button = controlItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    @objc
    private func openSettingsFromMenu(_ sender: NSMenuItem) {
        showConfigurationWindow(relativeTo: screenFrame(for: controlStatusView))
    }

    @objc
    private func quitFromMenu(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func showConfigurationWindow(relativeTo controlFrame: CGRect?) {
        store.refreshLaunchAtLoginStatus()
        store.refreshMenuBarItems()
        store.enableKeepOnlySelectedVisibleIfNeeded()
        positionConfigurationWindow(relativeTo: controlFrame)
        configurationWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureItemManagement() {
        store.onRefreshMenuBarItems = { [weak self] in
            guard let self else {
                return []
            }

            return self.currentManagedMenuBarItems()
        }

        store.onMoveMenuBarItem = { [weak self] item, visibility in
            guard let self else {
                return false
            }

            return await self.moveManagedMenuBarItem(item, to: visibility)
        }

        store.onPlaceMenuBarItem = { [weak self] item, target, section in
            guard let self else {
                return false
            }

            return await self.placeManagedMenuBarItem(item, before: target, in: section)
        }
    }

    private func applySettings(_ settings: MenuBarSettings) {
        controlItem?.length = CGFloat(MenuBarLayoutPolicy.controlWidth)

        if let button = controlStatusView {
            button.toolTip = settings.isCollapsed
                ? "MenuBarManager: hidden items are collapsed"
                : "MenuBarManager: hidden items are visible"
        }

        updateHiddenDivider(for: settings)
        scheduleSavedItemVisibilitySync(for: settings)
        if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_WRITE_DIAGNOSTICS_AFTER_SYNC"] == "1" {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                writeDiagnostics()
            }
        }
    }

    private func scheduleDiagnosticsIfNeeded() {
        guard ProcessInfo.processInfo.environment["MENUBAR_MANAGER_VISUAL_DIAGNOSTICS"] == "1" else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            store.setHiddenWidth(MenuBarSettings.defaults.hiddenWidth)
            store.setCollapsed(false)

            try? await Task.sleep(for: .milliseconds(250))
            diagnosticExpandedProbeFrame = screenFrame(for: diagnosticProbeItem?.button)
            diagnosticExpandedControlFrame = screenFrame(for: controlStatusView)
            diagnosticExpandedDividerFrame = screenFrame(for: hiddenDividerItem?.button)
            let expandedItems = RealMenuBarItemReader.snapshots()
            diagnosticExpandedRealMenuBarItemCount = expandedItems.count
            diagnosticExpandedVisibleRealMenuBarItemCount = expandedItems.filter(\.isOnScreen).count
            let expandedProbeWindow = menuBarItem(
                containingHorizontalCenterOf: diagnosticExpandedProbeFrame,
                in: expandedItems
            )
            diagnosticExpandedProbeWindowID = expandedProbeWindow?.windowID
            diagnosticExpandedProbeWasInsideScreen = isHorizontallyOnScreen(
                expandedProbeWindow?.frame ?? diagnosticExpandedProbeFrame
            )

            if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_APPLY_DIAGNOSTIC_VISIBILITY_RULES"] == "1" {
                await applySavedItemVisibilityRules(store.settings.itemVisibilities)
                try? await Task.sleep(for: .milliseconds(250))
            }

            store.setCollapsed(true)
            if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_REPOSITION_CONTROL_ITEM"] == "1" {
                await repositionControlItemForDiagnostics()
            }
            if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_REVEAL_PRIVATE_HIDDEN_ITEMS"] == "1" {
                await revealHiddenMenuBarItemsNearControlForDiagnostics()
            }
            if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_ENABLE_PRIVATE_ITEM_MOVES"] == "1" {
                await performPrivateCollapseMoveForDiagnostics()
            }

            if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_APPLY_DIAGNOSTIC_VISIBILITY_RULES"] != "1" {
                showConfigurationWindow(relativeTo: screenFrame(for: controlStatusView))
            }

            try? await Task.sleep(for: .milliseconds(500))
            if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_RESTORE_AFTER_PRIVATE_ITEM_MOVES"] == "1" {
                await restorePrivateMoveAfterDiagnostics()
            }

            if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_REVEAL_AFTER_DIAGNOSTIC_COLLAPSE"] == "1" {
                writeDiagnostics()
                store.setCollapsed(false)
                try? await Task.sleep(for: .milliseconds(500))
            }

            writeDiagnostics()

            if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_EXIT_AFTER_DIAGNOSTICS"] == "1" {
                NSApp.terminate(nil)
            }
        }
    }

    private func scheduleRevealIfNeeded() {
        let shouldReveal = ProcessInfo.processInfo.environment["MENUBAR_MANAGER_REVEAL_ON_LAUNCH"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--reveal-on-launch")

        guard shouldReveal else {
            return
        }

        Task { @MainActor in
            for _ in 0..<10 {
                let controlFrame = screenFrame(for: controlStatusView)

                if controlFrame != nil {
                    showConfigurationWindow(relativeTo: controlFrame)
                    return
                }

                try? await Task.sleep(for: .milliseconds(150))
            }

            showConfigurationWindow(relativeTo: nil)
        }
    }

    private func writeDiagnostics() {
        guard let path = ProcessInfo.processInfo.environment["MENUBAR_MANAGER_DIAGNOSTICS_PATH"] else {
            return
        }

        let controlFrame = screenFrame(for: controlStatusView)
        let collapsedProbeFrame = screenFrame(for: diagnosticProbeItem?.button)
        let dividerFrame = screenFrame(for: hiddenDividerItem?.button)
        let popoverFrame = configurationWindow?.frame
        let realMenuBarItems = RealMenuBarItemReader.snapshots()
        let visibleRealMenuBarItems = realMenuBarItems.filter(\.isOnScreen)
        let controlMenuBarWindow = menuBarItem(containingHorizontalCenterOf: controlFrame, in: realMenuBarItems)
        let dividerMenuBarWindow = menuBarItem(containingHorizontalCenterOf: dividerFrame, in: realMenuBarItems)
        let diagnosticProbeMenuBarWindow = diagnosticExpandedProbeWindowID.flatMap { probeWindowID in
            realMenuBarItems.first { $0.windowID == probeWindowID }
        }
        let isDiagnosticProbeShiftedOffScreen = isHorizontallyOffScreen(
            diagnosticProbeMenuBarWindow?.frame ?? collapsedProbeFrame
        )

        let payload: [String: Any] = [
            "isCollapsed": store.isCollapsed,
            "controlFrame": dictionary(from: controlFrame),
            "hiddenDividerFrame": dictionary(from: dividerFrame),
            "hiddenDividerLength": Int((hiddenDividerItem?.length ?? 0).rounded()),
            "screenFrame": dictionary(from: NSScreen.main?.frame),
            "visibleFrame": dictionary(from: NSScreen.main?.visibleFrame),
            "safeAreaInsets": dictionary(from: NSScreen.main?.safeAreaInsets),
            "auxiliaryTopLeftArea": dictionary(from: NSScreen.main?.auxiliaryTopLeftArea),
            "auxiliaryTopRightArea": dictionary(from: NSScreen.main?.auxiliaryTopRightArea),
            "expandedControlFrame": dictionary(from: diagnosticExpandedControlFrame),
            "expandedHiddenDividerFrame": dictionary(from: diagnosticExpandedDividerFrame),
            "expandedProbeFrame": dictionary(from: diagnosticExpandedProbeFrame),
            "collapsedProbeFrame": dictionary(from: collapsedProbeFrame),
            "popoverFrame": dictionary(from: popoverFrame),
            "controlWidth": controlFrame?.width ?? 0,
            "controlIsInMenuBarSafeArea": isInMenuBarSafeArea(controlFrame),
            "expandedRealMenuBarItemCount": diagnosticExpandedRealMenuBarItemCount,
            "expandedVisibleRealMenuBarItemCount": diagnosticExpandedVisibleRealMenuBarItemCount,
            "realMenuBarItemCount": realMenuBarItems.count,
            "visibleRealMenuBarItemCount": visibleRealMenuBarItems.count,
            "currentAppMenuBarItemCount": realMenuBarItems.filter(\.isCurrentApp).count,
            "controlIsRepresentedByRealMenuBarWindow": controlMenuBarWindow != nil,
            "controlMenuBarWindow": controlMenuBarWindow?.dictionary ?? [:],
            "hiddenDividerIsRepresentedByRealMenuBarWindow": dividerMenuBarWindow != nil,
            "hiddenDividerMenuBarWindow": dividerMenuBarWindow?.dictionary ?? [:],
            "diagnosticProbeMenuBarWindow": diagnosticProbeMenuBarWindow?.dictionary ?? [:],
            "diagnosticProbeWindowID": diagnosticExpandedProbeWindowID.map(Int.init) ?? 0,
            "collapsedVisibleItemDelta": diagnosticExpandedVisibleRealMenuBarItemCount - visibleRealMenuBarItems.count,
            "privateMoveDiagnostics": privateMoveDiagnostics,
            "menuBarSyncDiagnostics": menuBarSyncDiagnostics,
            "visibilityPolicyMode": store.settings.visibilityPolicyMode.rawValue,
            "alwaysVisibleItemIDs": Array(store.settings.alwaysVisibleItemIDs).sorted(),
            "savedVisibilityRules": store.settings.itemVisibilities.mapValues(\.rawValue),
            "hiddenMenuBarWindowIDs": hiddenMenuBarWindowIDs.map(Int.init).sorted(),
            "realMenuBarItems": realMenuBarItems.map(\.dictionary),
            "diagnosticProbeIsHiddenWhenCollapsed": isDiagnosticProbeShiftedOffScreen,
            "diagnosticProbeIsVisibleWhenExpanded": diagnosticExpandedProbeWasInsideScreen,
            "popoverIsNearControl": popoverCoversControl(controlFrame: controlFrame, popoverFrame: popoverFrame),
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }

        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func isHorizontallyOffScreen(_ rect: CGRect?) -> Bool {
        guard let rect,
              let screenFrame = NSScreen.main?.frame else {
            return false
        }

        return rect.maxX <= screenFrame.minX + 1 || rect.minX >= screenFrame.maxX - 1
    }

    private func isHorizontallyOnScreen(_ rect: CGRect?) -> Bool {
        guard let rect,
              let screenFrame = NSScreen.main?.frame else {
            return false
        }

        return rect.maxX > screenFrame.minX + 1 && rect.minX < screenFrame.maxX - 1
    }

    private func isInMenuBarSafeArea(_ rect: CGRect?) -> Bool {
        guard let rect else {
            return false
        }

        guard let screen = screen(containing: rect) else {
            return false
        }

        if let auxiliaryTopRightArea = screen.auxiliaryTopRightArea,
           auxiliaryTopRightArea.intersects(rect) {
            return true
        }

        if let auxiliaryTopLeftArea = screen.auxiliaryTopLeftArea,
           auxiliaryTopLeftArea.intersects(rect) {
            return true
        }

        return screen.safeAreaInsets.top == 0 && screen.frame.intersects(rect)
    }

    private func screenFrame(for view: NSView?) -> CGRect? {
        guard let view, let window = view.window else {
            return nil
        }

        let windowFrame = view.convert(view.bounds, to: nil)
        return window.convertToScreen(windowFrame)
    }

    private func dictionary(from rect: CGRect?) -> [String: Double] {
        guard let rect else {
            return [:]
        }

        return [
            "x": rect.origin.x,
            "y": rect.origin.y,
            "width": rect.width,
            "height": rect.height,
            "minX": rect.minX,
            "maxX": rect.maxX,
            "minY": rect.minY,
            "maxY": rect.maxY,
            "midX": rect.midX,
            "midY": rect.midY,
        ]
    }

    private func dictionary(from insets: NSEdgeInsets?) -> [String: Double] {
        guard let insets else {
            return [:]
        }

        return [
            "top": insets.top,
            "left": insets.left,
            "bottom": insets.bottom,
            "right": insets.right,
        ]
    }

    private func popoverCoversControl(controlFrame: CGRect?, popoverFrame: CGRect?) -> Bool {
        guard let controlFrame, let popoverFrame else {
            return false
        }

        let isHorizontallyAligned = popoverFrame.minX <= controlFrame.midX
            && popoverFrame.maxX >= controlFrame.midX
        let isBelowControl = popoverFrame.maxY <= controlFrame.minY + 4

        return isHorizontallyAligned && isBelowControl
    }

    private func menuBarItem(
        containingHorizontalCenterOf controlFrame: CGRect?,
        in items: [RealMenuBarItemSnapshot]
    ) -> RealMenuBarItemSnapshot? {
        guard let controlFrame else {
            return nil
        }

        return items.first { item in
            item.frame.minX - 4 <= controlFrame.midX
                && item.frame.maxX + 4 >= controlFrame.midX
                && item.frame.width >= controlFrame.width - 8
        }
    }

    private func updateHiddenDivider(for settings: MenuBarSettings) {
        guard let hiddenDividerItem else {
            return
        }

        if settings.isCollapsed {
            hiddenDividerItem.length = CGFloat(MenuBarLayoutPolicy.hiddenDividerCollapsedLength)
            hiddenDividerItem.button?.cell?.isEnabled = false
            hiddenDividerItem.button?.isHighlighted = false
        } else {
            hiddenDividerItem.length = 1
        }
    }

    private func currentManagedMenuBarItems() -> [ManagedMenuBarItem] {
        let items = RealMenuBarItemReader.snapshots()
        let controlWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: controlStatusView),
            in: items
        )
        let dividerWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: hiddenDividerItem?.button),
            in: items
        )

        let manageableItems = items
            .filter { item in
                item.windowID != controlWindow?.windowID
                    && item.windowID != dividerWindow?.windowID
                    && !item.isCurrentApp
                    && item.alpha > 0
            }

        let identities = managedIdentities(for: manageableItems)

        return manageableItems
            .map { item in
                let identity = identities[item.windowID] ?? ManagedMenuBarItemIdentity(
                    windowID: item.windowID,
                    stableID: managedStableID(for: item),
                    displayName: managedDisplayName(for: item)
                )
                let stableID = identity.stableID
                let displayName = identity.displayName
                let preferredVisibility = store.settings.preferredVisibility(for: stableID)
                let canBeHidden = canManageMenuBarItem(item)
                let detail = managedDetail(for: item)
                return ManagedMenuBarItem(
                    id: item.runtimeID,
                    stableID: stableID,
                    displayName: displayName,
                    detail: detail,
                    sortX: item.frame.minX,
                    icon: icon(for: item),
                    section: section(for: item, dividerWindow: dividerWindow),
                    preferredVisibility: preferredVisibility,
                    canBeHidden: canBeHidden
                )
            }
            .sorted { lhs, rhs in
                if lhs.section != rhs.section {
                    return sectionSortKey(lhs.section) < sectionSortKey(rhs.section)
                }

                return lhs.sortX < rhs.sortX
            }
    }

    private func managedIdentities(
        for items: [RealMenuBarItemSnapshot]
    ) -> [CGWindowID: ManagedMenuBarItemIdentity] {
        var existingStableIDsByWindowID = managedStableIDsByWindowID
        if let diagnosticExpandedProbeWindowID {
            existingStableIDsByWindowID.removeValue(forKey: diagnosticExpandedProbeWindowID)
        }

        let identities = MenuBarItemIdentityResolver.resolve(
            items: items,
            existingStableIDsByWindowID: existingStableIDsByWindowID,
            stableIDForItem: { [weak self] item in
                self?.managedStableID(for: item) ?? item.stableID
            },
            displayNameForItem: { [weak self] item in
                self?.managedDisplayName(for: item) ?? item.displayName
            }
        )

        for identity in identities.values {
            managedStableIDsByWindowID[identity.windowID] = identity.stableID
        }

        return identities
    }

    private func moveManagedMenuBarItem(
        _ managedItem: ManagedMenuBarItem,
        to visibility: MenuBarItemVisibility
    ) async -> Bool {
        let items = RealMenuBarItemReader.snapshots()
        guard let item = items.first(where: { $0.runtimeID == managedItem.id }),
              canManageMenuBarItem(item) else {
            return false
        }

        switch visibility {
        case .hidden:
            let succeeded = await hideMenuBarItem(item, in: items)
            writeDiagnosticsAfterItemMoveIfNeeded()
            return succeeded
        case .visible:
            let succeeded = await showMenuBarItem(item, in: items)
            writeDiagnosticsAfterItemMoveIfNeeded()
            return succeeded
        }
    }

    private func placeManagedMenuBarItem(
        _ managedItem: ManagedMenuBarItem,
        before target: ManagedMenuBarItem?,
        in section: MenuBarItemSection
    ) async -> Bool {
        let visibility: MenuBarItemVisibility = section == .visible ? .visible : .hidden
        guard let target else {
            return await moveManagedMenuBarItem(managedItem, to: visibility)
        }
        guard target.id != managedItem.id else {
            return true
        }

        let wasCollapsed = store.isCollapsed
        if wasCollapsed {
            hiddenDividerItem?.length = 1
            try? await Task.sleep(for: .milliseconds(180))
        }

        defer {
            if wasCollapsed {
                updateHiddenDivider(for: store.settings)
            }
        }

        let items = RealMenuBarItemReader.snapshots()
        guard let item = items.first(where: { $0.runtimeID == managedItem.id }),
              let targetItem = items.first(where: { $0.runtimeID == target.id }),
              canManageMenuBarItem(item),
              canManageMenuBarItem(targetItem) else {
            return false
        }

        let destination = CGPoint(
            x: targetItem.frame.minX - 1,
            y: targetItem.frame.midY
        )
        let result = await RealMenuBarItemMover.move(item, to: destination, targetItem: targetItem)
        let updatedItems = RealMenuBarItemReader.snapshots()
        let updatedDividerWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: hiddenDividerItem?.button),
            in: updatedItems
        )
        guard let updatedItem = updatedItems.first(where: { $0.windowID == item.windowID }) else {
            return false
        }

        let updatedSection = self.section(for: updatedItem, dividerWindow: updatedDividerWindow)
        if result.frameChanged, updatedSection == section {
            switch visibility {
            case .hidden:
                hiddenMenuBarWindowIDs.insert(item.windowID)
            case .visible:
                hiddenMenuBarWindowIDs.remove(item.windowID)
            }
            writeDiagnosticsAfterItemMoveIfNeeded()
            return true
        }

        writeDiagnosticsAfterItemMoveIfNeeded()
        return false
    }

    private func writeDiagnosticsAfterItemMoveIfNeeded() {
        guard ProcessInfo.processInfo.environment["MENUBAR_MANAGER_WRITE_DIAGNOSTICS_AFTER_SYNC"] == "1" else {
            return
        }

        writeDiagnostics()
    }

    private func hideMenuBarItem(
        _ item: RealMenuBarItemSnapshot,
        in items: [RealMenuBarItemSnapshot]
    ) async -> Bool {
        if !store.isCollapsed {
            store.setCollapsed(true)
            try? await Task.sleep(for: .milliseconds(180))
        }

        let currentItems = RealMenuBarItemReader.snapshots()
        let currentItem = currentItems.first(where: { $0.windowID == item.windowID }) ?? item
        guard let dividerWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: hiddenDividerItem?.button),
            in: currentItems
        ) else {
            return false
        }

        let destination = CGPoint(x: dividerWindow.frame.minX, y: dividerWindow.frame.midY)
        let result = await RealMenuBarItemMover.move(currentItem, to: destination, targetItem: dividerWindow)
        if result.frameChanged || result.becameHidden || result.finalSnapshot?.isOnScreen == false {
            hiddenMenuBarWindowIDs.insert(item.windowID)
            return true
        }

        return false
    }

    private func showMenuBarItem(
        _ item: RealMenuBarItemSnapshot,
        in items: [RealMenuBarItemSnapshot]
    ) async -> Bool {
        let wasCollapsed = store.isCollapsed
        if wasCollapsed, !item.isOnScreen {
            hiddenDividerItem?.length = 1
            try? await Task.sleep(for: .milliseconds(180))
        }

        defer {
            if wasCollapsed {
                updateHiddenDivider(for: store.settings)
            }
        }

        let currentItems = RealMenuBarItemReader.snapshots()
        guard let currentItem = currentItems.first(where: { $0.windowID == item.windowID }),
              let controlWindow = menuBarItem(
                containingHorizontalCenterOf: screenFrame(for: controlStatusView),
                in: currentItems
              ) else {
            return false
        }

        let destination = CGPoint(x: max(0, controlWindow.frame.minX - 2), y: controlWindow.frame.midY)
        let result = await RealMenuBarItemMover.move(currentItem, to: destination, targetItem: controlWindow)
        if result.frameChanged, result.finalSnapshot?.isOnScreen == true {
            hiddenMenuBarWindowIDs.remove(item.windowID)
            return true
        }

        return false
    }

    private func scheduleSavedItemVisibilitySync(for settings: MenuBarSettings) {
        menuBarSyncTask?.cancel()

        guard (settings.visibilityPolicyMode == .keepOnlySelectedVisible || !settings.itemVisibilities.isEmpty),
              ProcessInfo.processInfo.environment["MENUBAR_MANAGER_DISABLE_AUTOMATIC_PRIVATE_ITEM_MOVES"] != "1" else {
            return
        }

        menuBarSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }

            await applyCurrentVisibilityPolicy(settings)
        }
    }

    private func applyCurrentVisibilityPolicy(_ settings: MenuBarSettings) async {
        switch settings.visibilityPolicyMode {
        case .manual:
            await applySavedItemVisibilityRules(settings.itemVisibilities)
        case .keepOnlySelectedVisible:
            await applySavedItemVisibilityRules(currentVisibilityPolicyRules(for: settings))
        }
    }

    private func currentVisibilityPolicyRules(for settings: MenuBarSettings) -> [String: MenuBarItemVisibility] {
        let items = RealMenuBarItemReader.snapshots()
        let controlWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: controlStatusView),
            in: items
        )
        let dividerWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: hiddenDividerItem?.button),
            in: items
        )
        let candidates = items.filter { item in
            item.windowID != controlWindow?.windowID
                && item.windowID != dividerWindow?.windowID
                && !item.isCurrentApp
                && item.alpha > 0
                && canManageMenuBarItem(item)
        }
        let identities = managedIdentities(for: candidates)

        return candidates.reduce(into: [String: MenuBarItemVisibility]()) { rules, item in
            guard let stableID = identities[item.windowID]?.stableID else {
                return
            }

            rules[stableID] = settings.preferredVisibility(for: stableID)
        }
    }

    private func applySavedItemVisibilityRules(_ rules: [String: MenuBarItemVisibility]) async {
        guard !rules.isEmpty else {
            return
        }

        var results: [[String: Any]] = []
        for (stableID, visibility) in rules.sorted(by: { $0.key < $1.key }) {
            let items = RealMenuBarItemReader.snapshots()
            let controlWindow = menuBarItem(
                containingHorizontalCenterOf: screenFrame(for: controlStatusView),
                in: items
            )
            let dividerWindow = menuBarItem(
                containingHorizontalCenterOf: screenFrame(for: hiddenDividerItem?.button),
                in: items
            )
            let candidates = items.filter { item in
                item.windowID != controlWindow?.windowID
                    && item.windowID != dividerWindow?.windowID
                    && !item.isCurrentApp
                    && item.alpha > 0
            }
            let identities = managedIdentities(for: candidates)
            guard let item = candidates.first(where: { identities[$0.windowID]?.stableID == stableID }),
                  canManageMenuBarItem(item) else {
                continue
            }

            let currentSection = section(for: item, dividerWindow: dividerWindow)
            if currentSection == .hidden && visibility == .hidden
                || currentSection == .visible && visibility == .visible {
                switch visibility {
                case .hidden:
                    hiddenMenuBarWindowIDs.insert(item.windowID)
                case .visible:
                    hiddenMenuBarWindowIDs.remove(item.windowID)
                }

                results.append([
                    "stableID": stableID,
                    "visibility": visibility.rawValue,
                    "windowID": Int(item.windowID),
                    "succeeded": true,
                    "skipped": true,
                    "finalSnapshot": RealMenuBarItemReader.snapshot(windowID: item.windowID)?.dictionary ?? [:],
                ])
                continue
            }

            let succeeded = switch visibility {
            case .hidden:
                await hideMenuBarItem(item, in: items)
            case .visible:
                await showMenuBarItem(item, in: items)
            }

            results.append([
                "stableID": stableID,
                "visibility": visibility.rawValue,
                "windowID": Int(item.windowID),
                "succeeded": succeeded,
                "finalSnapshot": RealMenuBarItemReader.snapshot(windowID: item.windowID)?.dictionary ?? [:],
            ])
        }

        menuBarSyncDiagnostics = [
            "mode": "savedItemVisibility",
            "results": results,
        ]
        store.refreshMenuBarItems()
    }

    private func section(
        for item: RealMenuBarItemSnapshot,
        dividerWindow: RealMenuBarItemSnapshot?
    ) -> MenuBarItemSection {
        guard canManageMenuBarItem(item) else {
            return .protected
        }

        if !item.isOnScreen {
            return .hidden
        }

        if let dividerWindow,
           item.frame.maxX <= dividerWindow.frame.minX + 2 {
            return .hidden
        }

        return .visible
    }

    private func sectionSortKey(_ section: MenuBarItemSection) -> Int {
        switch section {
        case .visible: 0
        case .hidden: 1
        case .protected: 2
        }
    }

    private func canManageMenuBarItem(_ item: RealMenuBarItemSnapshot) -> Bool {
        !protectedMenuBarItemStableIDs.contains(item.stableID)
    }

    private func managedStableID(for item: RealMenuBarItemSnapshot) -> String {
        if diagnosticExpandedProbeWindowID == item.windowID {
            return diagnosticProbeIdentifier
        }

        return item.stableID
    }

    private func managedDisplayName(for item: RealMenuBarItemSnapshot) -> String {
        if diagnosticExpandedProbeWindowID == item.windowID {
            return diagnosticProbeIdentifier
        }

        return item.displayName
    }

    private func managedDetail(for item: RealMenuBarItemSnapshot) -> String {
        var parts: [String] = []

        if let bundleIdentifier = item.bundleIdentifier, !bundleIdentifier.isEmpty {
            parts.append(bundleIdentifier)
        } else if let ownerName = item.ownerName, !ownerName.isEmpty {
            parts.append(ownerName)
        }

        if let title = RealMenuBarItemSnapshot.userFacingTitle(item.bestTitle) {
            let readableTitle = RealMenuBarItemSnapshot.humanizedMenuBarTitle(title)
            if readableTitle != item.displayName {
                parts.append(readableTitle)
            }
        }

        parts.append("x \(Int(item.frame.minX))")
        parts.append("id \(item.windowID)")
        return parts.joined(separator: " · ")
    }

    private func icon(for item: RealMenuBarItemSnapshot) -> NSImage? {
        if let cachedIcon = menuBarIconCache[item.windowID] {
            return cachedIcon
        }

        scheduleMenuBarIconCapture(for: item)

        if item.bundleIdentifier == "com.apple.controlcenter" {
            return nil
        }

        return NSRunningApplication(processIdentifier: item.ownerPID)?.icon
    }

    private func scheduleMenuBarIconCapture(for item: RealMenuBarItemSnapshot) {
        guard ProcessInfo.processInfo.environment["MENUBAR_MANAGER_UI_TESTING"] != "1",
              CGPreflightScreenCaptureAccess(),
              item.isOnScreen,
              menuBarIconCache[item.windowID] == nil,
              !pendingMenuBarIconCaptures.contains(item.windowID) else {
            return
        }

        pendingMenuBarIconCaptures.insert(item.windowID)
        let windowID = item.windowID
        let itemSize = item.frame.size

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer {
                pendingMenuBarIconCaptures.remove(windowID)
            }

            guard let image = await Self.captureMenuBarIconImage(windowID: windowID) else {
                return
            }

            let size = NSSize(width: itemSize.width, height: itemSize.height)
            menuBarIconCache[windowID] = NSImage(cgImage: image, size: size)
            store.refreshMenuBarItems()
        }
    }

    private static func captureMenuBarIconImage(windowID: CGWindowID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            configuration.width = max(1, Int(window.frame.width * scale))
            configuration.height = max(1, Int(window.frame.height * scale))
            configuration.scalesToFit = true
            configuration.showsCursor = false
            configuration.capturesAudio = false

            return await withCheckedContinuation { continuation in
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                    continuation.resume(returning: image)
                }
            }
        } catch {
            return nil
        }
    }

    private var protectedMenuBarItemStableIDs: Set<String> {
        [
            "com.apple.controlcenter:Clock:Control Center",
            "com.apple.controlcenter:BentoBox:Control Center",
            "com.apple.controlcenter:BentoBox-0:Control Center",
            "com.apple.systemuiserver:Siri:SystemUIServer",
            "com.apple.controlcenter:AudioVideoModule:Control Center",
            "com.apple.controlcenter:FaceTime:Control Center",
            "com.apple.controlcenter:MusicRecognition:Control Center",
        ]
    }

    private func performPrivateCollapseMoveForDiagnostics() async {
        guard let topRightArea = NSScreen.main?.auxiliaryTopRightArea else {
            privateMoveDiagnostics = ["reason": "missing auxiliaryTopRightArea"]
            return
        }

        let beforeItems = RealMenuBarItemReader.snapshots()
        let controlWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: controlStatusView),
            in: beforeItems
        )

        guard let controlWindow else {
            privateMoveDiagnostics = ["reason": "missing control menu bar window"]
            return
        }

        let movableItems = beforeItems
            .filter(\.isOnScreen)
            .filter { item in
                item.windowID != controlWindow.windowID
                    && item.frame.maxX <= controlWindow.frame.minX + 1
                    && item.frame.minX >= topRightArea.minX
            }
            .prefix(2)

        guard !movableItems.isEmpty else {
            privateMoveDiagnostics = ["reason": "no visible items left of control"]
            return
        }

        let destination = CGPoint(x: max(0, topRightArea.minX - 18), y: controlWindow.frame.midY)
        let targetItem = beforeItems.first { item in
            item.frame.minX <= destination.x && item.frame.maxX >= destination.x
        } ?? controlWindow
        var movedWindowIDs: [Int] = []
        var moveResults: [[String: Any]] = []

        for item in movableItems {
            let result = await RealMenuBarItemMover.move(item, to: destination, targetItem: targetItem)
            moveResults.append(result.dictionary)
            if result.frameChanged {
                movedWindowIDs.append(Int(item.windowID))
            }
        }

        let afterItems = RealMenuBarItemReader.snapshots()
        let hiddenAfterMove = afterItems.filter { item in
            movedWindowIDs.contains(Int(item.windowID)) && !item.isOnScreen
        }
        privatelyMovedWindowIDs = movedWindowIDs.map { CGWindowID($0) }

        privateMoveDiagnostics = [
            "controlWindowID": Int(controlWindow.windowID),
            "targetWindowID": Int(targetItem.windowID),
            "destination": dictionary(from: CGRect(x: destination.x, y: destination.y, width: 0, height: 0)),
            "movedWindowIDs": movedWindowIDs,
            "moveResults": moveResults,
            "hiddenMovedWindowIDs": hiddenAfterMove.map { Int($0.windowID) },
            "requestedMoveCount": movableItems.count,
            "hiddenAfterMoveCount": hiddenAfterMove.count,
        ]
    }

    private func scheduleMenuBarSync(for settings: MenuBarSettings) {
        guard ProcessInfo.processInfo.environment["MENUBAR_MANAGER_DISABLE_AUTOMATIC_PRIVATE_ITEM_MOVES"] != "1" else {
            return
        }

        menuBarSyncTask?.cancel()
        menuBarSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else {
                return
            }

            await syncMenuBarItems(for: settings)
        }
    }

    private func syncMenuBarItems(for settings: MenuBarSettings) async {
        if settings.isCollapsed {
            await collapseMenuBarItems(for: settings)
        } else {
            await revealMenuBarItems()
        }

        if ProcessInfo.processInfo.environment["MENUBAR_MANAGER_WRITE_DIAGNOSTICS_AFTER_SYNC"] == "1" {
            writeDiagnostics()
        }
    }

    private func collapseMenuBarItems(for settings: MenuBarSettings) async {
        guard let topRightArea = NSScreen.main?.auxiliaryTopRightArea else {
            menuBarSyncDiagnostics = ["reason": "missing auxiliaryTopRightArea"]
            return
        }

        var items = RealMenuBarItemReader.snapshots()
        guard var controlWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: controlStatusView),
            in: items
        ) else {
            menuBarSyncDiagnostics = ["reason": "missing control menu bar window"]
            return
        }

        if !controlWindow.isOnScreen {
            await repositionControlItemForDiagnostics()
            items = RealMenuBarItemReader.snapshots()
            guard let repositionedControlWindow = menuBarItem(
                containingHorizontalCenterOf: screenFrame(for: controlStatusView),
                in: items
            ), repositionedControlWindow.isOnScreen else {
                menuBarSyncDiagnostics = ["reason": "control window is not on screen"]
                return
            }
            controlWindow = repositionedControlWindow
        }

        let hiddenSpan = CGFloat(MenuBarLayoutPolicy.targetHiddenSpan(for: settings))
        let minHiddenX = max(topRightArea.minX, controlWindow.frame.minX - hiddenSpan)
        let destination = CGPoint(x: max(0, topRightArea.minX - 18), y: controlWindow.frame.midY)
        let targetItem = items.first { item in
            item.frame.minX <= destination.x && item.frame.maxX >= destination.x
        } ?? controlWindow
        let candidates = items
            .filter(\.isOnScreen)
            .filter { item in
                item.windowID != controlWindow.windowID
                    && !hiddenMenuBarWindowIDs.contains(item.windowID)
                    && item.frame.maxX <= controlWindow.frame.minX + 1
                    && item.frame.minX >= minHiddenX
                    && item.frame.minX >= topRightArea.minX
            }
            .sorted { $0.frame.maxX > $1.frame.maxX }

        var results: [[String: Any]] = []
        for item in candidates {
            let result = await RealMenuBarItemMover.move(item, to: destination, targetItem: targetItem)
            results.append(result.dictionary)
            if result.frameChanged || result.becameHidden {
                hiddenMenuBarWindowIDs.insert(item.windowID)
            }
        }

        let afterItems = RealMenuBarItemReader.snapshots()
        let hiddenAfterMove = afterItems.filter { item in
            hiddenMenuBarWindowIDs.contains(item.windowID) && !item.isOnScreen
        }

        menuBarSyncDiagnostics = [
            "mode": "collapse",
            "controlWindowID": Int(controlWindow.windowID),
            "targetWindowID": Int(targetItem.windowID),
            "candidateWindowIDs": candidates.map { Int($0.windowID) },
            "hiddenAfterMoveWindowIDs": hiddenAfterMove.map { Int($0.windowID) },
            "moveResults": results,
        ]
    }

    private func revealMenuBarItems() async {
        var items = RealMenuBarItemReader.snapshots()
        let topRightArea = NSScreen.main?.auxiliaryTopRightArea
        guard var controlWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: controlStatusView),
            in: items
        ) else {
            menuBarSyncDiagnostics = ["reason": "missing control menu bar window"]
            return
        }

        if !controlWindow.isOnScreen {
            await repositionControlItemForDiagnostics()
            items = RealMenuBarItemReader.snapshots()
            if let repositionedControlWindow = menuBarItem(
                containingHorizontalCenterOf: screenFrame(for: controlStatusView),
                in: items
            ) {
                controlWindow = repositionedControlWindow
            }
        }

        let inferredHiddenWindowIDs = items
            .filter { item in
                guard let topRightArea else {
                    return false
                }

                return !item.isOnScreen
                    && item.windowID != controlWindow.windowID
                    && item.frame.maxX >= topRightArea.minX - 96
                    && item.frame.minX <= controlWindow.frame.minX
            }
            .map(\.windowID)
        let windowIDsToReveal = hiddenMenuBarWindowIDs.union(inferredHiddenWindowIDs)
        let itemsToReveal = items
            .filter { windowIDsToReveal.contains($0.windowID) }
            .sorted { $0.frame.minX > $1.frame.minX }

        guard !itemsToReveal.isEmpty else {
            menuBarSyncDiagnostics = [
                "mode": "reveal",
                "revealedWindowIDs": [],
                "reason": "no runtime hidden items",
            ]
            return
        }

        let destination = CGPoint(x: max(0, controlWindow.frame.minX - 2), y: controlWindow.frame.midY)
        var results: [[String: Any]] = []
        var revealedWindowIDs: [Int] = []

        for item in itemsToReveal {
            let result = await RealMenuBarItemMover.move(item, to: destination, targetItem: controlWindow)
            results.append(result.dictionary)
            if result.frameChanged && result.finalSnapshot?.isOnScreen == true {
                hiddenMenuBarWindowIDs.remove(item.windowID)
                revealedWindowIDs.append(Int(item.windowID))
            }
        }

        menuBarSyncDiagnostics = [
            "mode": "reveal",
            "controlWindowID": Int(controlWindow.windowID),
            "inferredHiddenWindowIDs": inferredHiddenWindowIDs.map(Int.init).sorted(),
            "revealedWindowIDs": revealedWindowIDs,
            "remainingHiddenWindowIDs": hiddenMenuBarWindowIDs.map(Int.init).sorted(),
            "moveResults": results,
        ]
    }

    private func restorePrivateMoveAfterDiagnostics() async {
        guard !privatelyMovedWindowIDs.isEmpty else {
            return
        }

        let currentItems = RealMenuBarItemReader.snapshots()
        guard let controlWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: controlStatusView),
            in: currentItems
        ) else {
            return
        }

        let destination = CGPoint(x: max(0, controlWindow.frame.minX - 2), y: controlWindow.frame.midY)
        let movedItems = currentItems.filter { item in
            privatelyMovedWindowIDs.contains(item.windowID)
        }

        for item in movedItems.reversed() {
            _ = await RealMenuBarItemMover.move(item, to: destination, targetItem: controlWindow)
        }

        var diagnostics = privateMoveDiagnostics
        diagnostics["restoreAttempted"] = true
        diagnostics["restoreDestination"] = dictionary(from: CGRect(x: destination.x, y: destination.y, width: 0, height: 0))
        privateMoveDiagnostics = diagnostics
    }

    private func revealHiddenMenuBarItemsNearControlForDiagnostics() async {
        guard let topRightArea = NSScreen.main?.auxiliaryTopRightArea else {
            return
        }

        let currentItems = RealMenuBarItemReader.snapshots()
        guard let controlWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: controlStatusView),
            in: currentItems
        ) else {
            return
        }

        let hiddenItems = currentItems.filter { item in
            !item.isOnScreen
                && item.windowID != controlWindow.windowID
                && item.frame.maxX >= topRightArea.minX - 96
                && item.frame.minX <= controlWindow.frame.minX
        }
        let destination = CGPoint(x: max(0, controlWindow.frame.minX - 2), y: controlWindow.frame.midY)

        for item in hiddenItems.reversed() {
            _ = await RealMenuBarItemMover.move(item, to: destination, targetItem: controlWindow)
        }
    }

    private func repositionControlItemForDiagnostics() async {
        let currentItems = RealMenuBarItemReader.snapshots()
        guard let controlWindow = menuBarItem(
            containingHorizontalCenterOf: screenFrame(for: controlStatusView),
            in: currentItems
        ), !controlWindow.isOnScreen else {
            return
        }

        guard let targetItem = currentItems.first(where: { item in
            item.isOnScreen && item.frame.minX > controlWindow.frame.maxX
        }) ?? currentItems.last(where: \.isOnScreen) else {
            return
        }

        let destination = CGPoint(x: targetItem.frame.midX, y: targetItem.frame.midY)
        _ = await RealMenuBarItemMover.move(controlWindow, to: destination, targetItem: targetItem)
    }

    private func positionConfigurationWindow(relativeTo controlFrame: CGRect?) {
        guard let configurationWindow else {
            return
        }

        guard let controlFrame else {
            let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_512, height: 982)
            configurationWindow.setFrameOrigin(NSPoint(
                x: visibleFrame.maxX - configurationWindow.frame.width - 12,
                y: visibleFrame.maxY - configurationWindow.frame.height - 12
            ))
            return
        }

        let panelFrame = configurationWindow.frame
        let desiredX = controlFrame.midX - (panelFrame.width / 2)
        let desiredY = controlFrame.minY - panelFrame.height - 8
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_512, height: 982)
        let horizontalPadding = 8.0
        let clampedX = min(
            max(desiredX, visibleFrame.minX + horizontalPadding),
            visibleFrame.maxX - panelFrame.width - horizontalPadding
        )

        configurationWindow.setFrameOrigin(NSPoint(x: clampedX, y: desiredY))
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(NSPoint(x: rect.midX, y: rect.midY))
        } ?? NSScreen.main
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        controlItem?.button?.highlight(false)
    }
}

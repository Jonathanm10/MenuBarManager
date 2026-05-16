import XCTest

@MainActor
final class MenuBarManagerUITests: XCTestCase {
    func testDiagnosticSettingsWindowIsVisibleAndCompact() {
        let app = launchDiagnosticApp()

        let settingsWindow = app.dialogs["MenuBarManagerSettingsWindow"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5), "MenuBarManager settings window should be visible.")
        XCTAssertGreaterThan(settingsWindow.frame.width, 400)

        XCTAssertTrue(settingsWindow.staticTexts["Hidden"].exists, "Settings window should show the collapsed state.")
        XCTAssertTrue(settingsWindow.buttons["Refresh"].exists, "Settings window should expose a manual refresh.")
        XCTAssertTrue(settingsWindow.textFields["Search items"].exists, "Settings window should expose item search.")
        XCTAssertTrue(settingsWindow.checkBoxes["Open at login"].exists, "Settings window should keep app-level settings available.")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "MenuBarManager diagnostic settings window"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testDiagnosticsExposeRealMenuBarItemsAndControlWindow() throws {
        let diagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarManager-\(UUID().uuidString)-diagnostics.json")
        let app = launchDiagnosticApp(diagnosticsPath: diagnosticsURL.path, includesProbeItem: true)

        let diagnostics = try waitForDiagnostics(at: diagnosticsURL)
        let controlFrame = try frame(named: "controlFrame", in: diagnostics)
        let menuBarFrame = try frame(named: "auxiliaryTopRightArea", in: diagnostics)
        let realMenuBarItems = try XCTUnwrap(
            diagnostics["realMenuBarItems"] as? [[String: Any]],
            "Missing real menu bar items in \(diagnostics)."
        )

        XCTAssertTrue(
            try bool(named: "isCollapsed", in: diagnostics),
            "Diagnostics should capture collapsed state. Data: \(diagnostics)"
        )
        XCTAssertGreaterThan(
            try int(named: "realMenuBarItemCount", in: diagnostics),
            0,
            "CGS should expose real menu bar item windows. Data: \(diagnostics)"
        )
        XCTAssertGreaterThan(
            try int(named: "visibleRealMenuBarItemCount", in: diagnostics),
            0,
            "At least one real menu bar item should be on screen. Data: \(diagnostics)"
        )
        XCTAssertTrue(
            try bool(named: "controlIsRepresentedByRealMenuBarWindow", in: diagnostics),
            "The AppKit status item should match a real menu bar window. Data: \(diagnostics)"
        )
        let controlMenuBarWindow = try dictionary(named: "controlMenuBarWindow", in: diagnostics)
        XCTAssertFalse(
            controlMenuBarWindow.isEmpty,
            "Diagnostics should include the real menu bar window that contains MB. Data: \(diagnostics)"
        )
        XCTAssertFalse(realMenuBarItems.isEmpty)
        XCTAssertGreaterThan(
            controlFrame["minX", default: 0],
            menuBarFrame["minX", default: 0],
            "MB should remain inside the notch-safe menu bar area."
        )
        XCTAssertLessThan(
            controlFrame["maxX", default: 0],
            menuBarFrame["maxX", default: 0],
            "MB should remain inside the notch-safe menu bar area."
        )

        add(XCTAttachment(string: "\(diagnostics)"))
        app.terminate()
    }

    func testDiagnosticsWaitRetriesPartialWrites() throws {
        let diagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarManager-\(UUID().uuidString)-partial-diagnostics.json")
        defer {
            try? FileManager.default.removeItem(at: diagnosticsURL)
        }

        try Data("{".utf8).write(to: diagnosticsURL)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            try? Data(#"{"ready":true}"#.utf8).write(to: diagnosticsURL, options: .atomic)
        }

        let diagnostics = try waitForDiagnostics(at: diagnosticsURL) { diagnostics in
            diagnostics["ready"] as? Bool == true
        }

        XCTAssertEqual(diagnostics["ready"] as? Bool, true)
    }

    func testCollapsedDiagnosticsExposeHiddenRealMenuBarItems() throws {
        let diagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarManager-\(UUID().uuidString)-private-move-diagnostics.json")
        let app = launchDiagnosticApp(
            diagnosticsPath: diagnosticsURL.path,
            includesProbeItem: true
        )

        let diagnostics = try waitForDiagnostics(at: diagnosticsURL)
        XCTAssertEqual(
            try int(named: "hiddenDividerLength", in: diagnostics),
            10_000,
            "Collapsed state should expand the real hidden divider item. Data: \(diagnostics)"
        )
        XCTAssertTrue(
            try bool(named: "diagnosticProbeIsVisibleWhenExpanded", in: diagnostics),
            "The diagnostic menu bar item should be visible before collapse. Data: \(diagnostics)"
        )
        XCTAssertTrue(
            try bool(named: "diagnosticProbeIsHiddenWhenCollapsed", in: diagnostics),
            "The expanded hidden divider should push a real diagnostic menu bar item offscreen. Data: \(diagnostics)"
        )
        XCTAssertGreaterThan(
            try int(named: "realMenuBarItemCount", in: diagnostics),
            try int(named: "visibleRealMenuBarItemCount", in: diagnostics),
            "Collapsed diagnostics should expose hidden real menu bar windows. Data: \(diagnostics)"
        )

        add(XCTAttachment(string: "\(diagnostics)"))
        app.terminate()
    }

    func testDiagnosticRevealShrinksDividerAndRevealsMenuBarItems() throws {
        let diagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarManager-\(UUID().uuidString)-reveal-diagnostics.json")
        let app = launchDiagnosticApp(
            diagnosticsPath: diagnosticsURL.path,
            includesProbeItem: true,
            revealsAfterDiagnosticCollapse: true,
            writesDiagnosticsAfterSync: true
        )

        let collapsedDiagnostics = try waitForDiagnostics(at: diagnosticsURL) { diagnostics in
            (diagnostics["isCollapsed"] as? Bool) == true
                && (diagnostics["hiddenDividerLength"] as? Int) == 10_000
                && (diagnostics["diagnosticProbeIsHiddenWhenCollapsed"] as? Bool) == true
        }
        XCTAssertTrue(
            try bool(named: "diagnosticProbeIsHiddenWhenCollapsed", in: collapsedDiagnostics),
            "Collapsed state should hide the diagnostic probe before reveal. Data: \(collapsedDiagnostics)"
        )

        let revealDiagnostics = try waitForDiagnostics(at: diagnosticsURL) { diagnostics in
            (diagnostics["isCollapsed"] as? Bool) == false
                && (diagnostics["hiddenDividerLength"] as? Int) == 1
        }
        XCTAssertGreaterThan(
            try int(named: "hiddenDividerLength", in: collapsedDiagnostics),
            try int(named: "hiddenDividerLength", in: revealDiagnostics),
            "Show now should shrink the divider. Data: \(revealDiagnostics)"
        )
        XCTAssertFalse(
            try bool(named: "diagnosticProbeIsHiddenWhenCollapsed", in: revealDiagnostics),
            "Show now should bring the diagnostic menu bar item back onscreen. Data: \(revealDiagnostics)"
        )

        add(XCTAttachment(string: "\(revealDiagnostics)"))
        app.terminate()
    }

    func testItemManagerCanRevealSpecificHiddenDiagnosticItem() throws {
        let diagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarManager-\(UUID().uuidString)-item-manager-diagnostics.json")
        let app = launchDiagnosticApp(
            diagnosticsPath: diagnosticsURL.path,
            includesProbeItem: true,
            writesDiagnosticsAfterSync: true
        )

        _ = try waitForDiagnostics(at: diagnosticsURL) { diagnostics in
            (diagnostics["isCollapsed"] as? Bool) == true
                && (diagnostics["diagnosticProbeIsHiddenWhenCollapsed"] as? Bool) == true
        }

        let visibleToggle = app.checkBoxes["Visible MenuBarManagerDiagnosticProbe.v1"]
        XCTAssertTrue(visibleToggle.waitForExistence(timeout: 5), "The hidden diagnostic probe should expose a Visible checkbox.")
        visibleToggle.click()

        let revealDiagnostics = try waitForDiagnostics(at: diagnosticsURL) { diagnostics in
            (diagnostics["diagnosticProbeIsHiddenWhenCollapsed"] as? Bool) == false
        }
        XCTAssertFalse(
            try bool(named: "diagnosticProbeIsHiddenWhenCollapsed", in: revealDiagnostics),
            "The per-item Show action should bring the diagnostic probe back onscreen. Data: \(revealDiagnostics)"
        )

        add(XCTAttachment(string: "\(revealDiagnostics)"))
        app.terminate()
    }

    private func launchDiagnosticApp(
        diagnosticsPath: String? = nil,
        includesProbeItem: Bool = false,
        enablesPrivateItemMoves: Bool = false,
        revealsAfterDiagnosticCollapse: Bool = false,
        writesDiagnosticsAfterSync: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MENUBAR_MANAGER_VISUAL_DIAGNOSTICS"] = "1"
        app.launchEnvironment["MENUBAR_MANAGER_UI_TESTING"] = "1"
        app.launchEnvironment["MENUBAR_MANAGER_REPOSITION_CONTROL_ITEM"] = "1"

        if let diagnosticsPath {
            app.launchEnvironment["MENUBAR_MANAGER_DIAGNOSTICS_PATH"] = diagnosticsPath
        }

        if includesProbeItem {
            app.launchEnvironment["MENUBAR_MANAGER_DIAGNOSTIC_PROBE_ITEM"] = "1"
        }

        if enablesPrivateItemMoves {
            app.launchEnvironment["MENUBAR_MANAGER_ENABLE_PRIVATE_ITEM_MOVES"] = "1"
            app.launchEnvironment["MENUBAR_MANAGER_RESTORE_AFTER_PRIVATE_ITEM_MOVES"] = "1"
        }

        if revealsAfterDiagnosticCollapse {
            app.launchEnvironment["MENUBAR_MANAGER_REVEAL_AFTER_DIAGNOSTIC_COLLAPSE"] = "1"
        }

        if writesDiagnosticsAfterSync {
            app.launchEnvironment["MENUBAR_MANAGER_WRITE_DIAGNOSTICS_AFTER_SYNC"] = "1"
        }

        addTeardownBlock {
            app.terminate()
        }

        app.launch()
        app.activate()
        return app
    }

    private func waitForDiagnostics(at url: URL) throws -> [String: Any] {
        try waitForDiagnostics(at: url) { _ in true }
    }

    private func waitForDiagnostics(
        at url: URL,
        matching predicate: ([String: Any]) -> Bool
    ) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(5)
        var lastReadError: Error?

        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    let object = try JSONSerialization.jsonObject(with: data)
                    let diagnostics = try XCTUnwrap(object as? [String: Any])
                    lastReadError = nil
                    if predicate(diagnostics) {
                        return diagnostics
                    }
                } catch {
                    lastReadError = error
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        if let lastReadError {
            XCTFail("Timed out waiting for diagnostics at \(url.path). Last read error: \(lastReadError).")
        } else {
            XCTFail("Timed out waiting for diagnostics at \(url.path).")
        }
        return [:]
    }

    private func frame(named name: String, in diagnostics: [String: Any]) throws -> [String: Double] {
        let frame = try XCTUnwrap(diagnostics[name] as? [String: Double], "Missing frame '\(name)' in \(diagnostics).")
        XCTAssertFalse(frame.isEmpty, "Frame '\(name)' should not be empty.")
        return frame
    }

    private func bool(named name: String, in diagnostics: [String: Any]) throws -> Bool {
        try XCTUnwrap(diagnostics[name] as? Bool, "Missing boolean '\(name)' in \(diagnostics).")
    }

    private func int(named name: String, in diagnostics: [String: Any]) throws -> Int {
        try XCTUnwrap(diagnostics[name] as? Int, "Missing integer '\(name)' in \(diagnostics).")
    }

    private func dictionary(named name: String, in diagnostics: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(diagnostics[name] as? [String: Any], "Missing dictionary '\(name)' in \(diagnostics).")
    }

    private func intArray(named name: String, in diagnostics: [String: Any]) throws -> [Int] {
        try XCTUnwrap(diagnostics[name] as? [Int], "Missing integer array '\(name)' in \(diagnostics).")
    }
}

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetWindowCount")
private func CGSGetWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowCount")
private func CGSGetOnScreenWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowList")
private func CGSGetOnScreenWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
private func CGSGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
private func CGSGetScreenRectForWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outRect: inout CGRect
) -> CGError

struct RealMenuBarItemSnapshot: Equatable {
    static let unlabeledMenuBarItemDisplayName = "Unlabeled menu item"

    let windowID: CGWindowID
    let frame: CGRect
    let title: String?
    let ownerPID: pid_t
    let ownerName: String?
    let bundleIdentifier: String?
    let accessibilityTitle: String?
    let layer: Int
    let alpha: Double
    let isOnScreen: Bool
    let isCurrentApp: Bool

    var runtimeID: String {
        String(windowID)
    }

    var stableID: String {
        [
            bundleIdentifier ?? "<unknown-bundle>",
            Self.stableIdentityTitle(for: bestTitle) ?? "",
            ownerName ?? "",
        ].joined(separator: ":")
    }

    var bestTitle: String? {
        if let accessibilityTitle, !accessibilityTitle.isEmpty {
            return accessibilityTitle
        }

        return title
    }

    var displayName: String {
        let fallback = Self.userFacingTitle(bestTitle) ?? ownerName ?? "Unknown item"
        guard let bundleIdentifier else {
            return fallback
        }

        if bundleIdentifier == "com.apple.controlcenter" {
            return Self.controlCenterDisplayName(for: bestTitle)
                ?? Self.unlabeledMenuBarItemDisplayName
        }

        if bundleIdentifier == "com.apple.systemuiserver" {
            return Self.systemUIServerDisplayName(for: bestTitle)
                ?? Self.userFacingTitle(bestTitle)
                ?? "System menu item"
        }

        if let appName = NSRunningApplication(processIdentifier: ownerPID)?.localizedName {
            return appName
        }

        return fallback
    }

    var detail: String {
        let titleText = Self.userFacingTitle(bestTitle)
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            if let titleText {
                let readableTitle = Self.humanizedMenuBarTitle(titleText)
                if readableTitle != displayName {
                    return "\(bundleIdentifier) / \(readableTitle)"
                }
            }

            return bundleIdentifier
        }

        return titleText ?? "Untitled"
    }

    var dictionary: [String: Any] {
        [
            "windowID": Int(windowID),
            "runtimeID": runtimeID,
            "stableID": stableID,
            "displayName": displayName,
            "frame": Self.dictionary(from: frame),
            "title": title ?? "",
            "accessibilityTitle": accessibilityTitle ?? "",
            "ownerPID": Int(ownerPID),
            "ownerName": ownerName ?? "",
            "bundleIdentifier": bundleIdentifier ?? "",
            "layer": layer,
            "alpha": alpha,
            "isOnScreen": isOnScreen,
            "isCurrentApp": isCurrentApp,
        ]
    }

    private static func controlCenterDisplayName(for title: String?) -> String? {
        guard let title = userFacingTitle(title) else {
            return nil
        }

        return switch title {
        case "Control Center":
            nil
        case "AccessibilityShortcuts": "Accessibility Shortcuts"
        case "BentoBox", "BentoBox-0": "Control Center"
        case "FocusModes": "Focus"
        case "KeyboardBrightness": "Keyboard Brightness"
        case "MusicRecognition": "Music Recognition"
        case "NowPlaying": "Now Playing"
        case "ScreenMirroring": "Screen Mirroring"
        case "StageManager": "Stage Manager"
        case "UserSwitcher": "Fast User Switching"
        case "WiFi": "Wi-Fi"
        case "Battery": "Battery"
        case "Clock": "Clock"
        default: humanizedMenuBarTitle(title)
        }
    }

    private static func systemUIServerDisplayName(for title: String?) -> String? {
        guard let title = userFacingTitle(title) else {
            return nil
        }

        return switch title {
        case "TimeMachine.TMMenuExtraHost", "TimeMachineMenuExtra.TMMenuExtraHost": "Time Machine"
        case "Siri": "Siri"
        default: humanizedMenuBarTitle(title)
        }
    }

    static func userFacingTitle(_ title: String?) -> String? {
        guard let title = normalizedTitle(title),
              !isOpaqueMenuBarTitle(title) else {
            return nil
        }

        return title
    }

    private static func stableIdentityTitle(for title: String?) -> String? {
        guard let title = normalizedTitle(title),
              !isOpaqueMenuBarTitle(title) else {
            return nil
        }

        return title
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        guard let title else {
            return nil
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isOpaqueMenuBarTitle(_ title: String) -> Bool {
        let opaquePatterns = [
            #"^Item-\d+$"#,
            #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
        ]

        return opaquePatterns.contains { pattern in
            title.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func humanizedMenuBarTitle(_ title: String) -> String {
        var humanized = title
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(
                of: #"(?<=[a-z0-9])(?=[A-Z])"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?<=[A-Z])(?=[A-Z][a-z])"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if humanized.hasSuffix(" Icon") {
            humanized.removeLast(" Icon".count)
        }

        guard let first = humanized.first else {
            return humanized
        }

        return first.uppercased() + humanized.dropFirst()
    }

    private static func dictionary(from rect: CGRect) -> [String: Double] {
        [
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
}

enum RealMenuBarItemReader {
    static func snapshots() -> [RealMenuBarItemSnapshot] {
        let menuBarWindowIDs = menuBarWindowIDs()
        guard !menuBarWindowIDs.isEmpty else {
            return []
        }

        let onScreenWindowIDs = Set(onScreenWindowIDs())
        let descriptions = windowDescriptions(for: menuBarWindowIDs)
        let ownerPIDs = Set(descriptions.values.compactMap { $0[kCGWindowOwnerPID] as? pid_t })
        let accessibilityItems = AccessibilityMenuBarItemReader.items(for: ownerPIDs)

        return menuBarWindowIDs.compactMap { windowID in
            guard let description = descriptions[windowID] else {
                return nil
            }

            let cgWindowFrame = frame(from: description)
            let cgsWindowFrame = cgsFrame(for: windowID)
            let frame = cgsWindowFrame ?? cgWindowFrame

            guard let frame,
                  let layer = description[kCGWindowLayer] as? Int,
                  layer == kCGStatusWindowLevel else {
                return nil
            }

            let ownerPID = description[kCGWindowOwnerPID] as? pid_t ?? 0
            let app = NSRunningApplication(processIdentifier: ownerPID)
            let accessibilityTitle = accessibilityItems.bestTitle(ownerPID: ownerPID, frame: frame)

            return RealMenuBarItemSnapshot(
                windowID: windowID,
                frame: frame,
                title: description[kCGWindowName] as? String,
                ownerPID: ownerPID,
                ownerName: description[kCGWindowOwnerName] as? String,
                bundleIdentifier: app?.bundleIdentifier,
                accessibilityTitle: accessibilityTitle,
                layer: layer,
                alpha: description[kCGWindowAlpha] as? Double ?? 0,
                isOnScreen: onScreenWindowIDs.contains(windowID)
                    || (description[kCGWindowIsOnscreen] as? Bool ?? false),
                isCurrentApp: ownerPID == ProcessInfo.processInfo.processIdentifier
            )
        }
        .sorted {
            if $0.frame.minX == $1.frame.minX {
                return $0.windowID < $1.windowID
            }

            return $0.frame.minX < $1.frame.minX
        }
    }

    static func onScreenSnapshots() -> [RealMenuBarItemSnapshot] {
        snapshots().filter(\.isOnScreen)
    }

    static func snapshot(windowID: CGWindowID) -> RealMenuBarItemSnapshot? {
        snapshots().first { $0.windowID == windowID }
    }

    private static func menuBarWindowIDs() -> [CGWindowID] {
        let windowCount = max(generalWindowCount(), 1)
        var list = [CGWindowID](repeating: 0, count: windowCount)
        var realCount: Int32 = 0
        let result = CGSGetProcessMenuBarWindowList(
            CGSMainConnectionID(),
            0,
            Int32(windowCount),
            &list,
            &realCount
        )

        guard result == .success else {
            return []
        }

        return Array(list.prefix(Int(realCount))).filter { $0 != 0 }
    }

    private static func onScreenWindowIDs() -> [CGWindowID] {
        let windowCount = max(onScreenWindowCount(), 1)
        var list = [CGWindowID](repeating: 0, count: windowCount)
        var realCount: Int32 = 0
        let result = CGSGetOnScreenWindowList(
            CGSMainConnectionID(),
            0,
            Int32(windowCount),
            &list,
            &realCount
        )

        guard result == .success else {
            return []
        }

        return Array(list.prefix(Int(realCount))).filter { $0 != 0 }
    }

    private static func generalWindowCount() -> Int {
        var count: Int32 = 0
        guard CGSGetWindowCount(CGSMainConnectionID(), 0, &count) == .success else {
            return 0
        }

        return Int(count)
    }

    private static func onScreenWindowCount() -> Int {
        var count: Int32 = 0
        guard CGSGetOnScreenWindowCount(CGSMainConnectionID(), 0, &count) == .success else {
            return 0
        }

        return Int(count)
    }

    private static func windowDescriptions(for windowIDs: [CGWindowID]) -> [CGWindowID: [CFString: Any]] {
        var rawPointers = windowIDs.map { UnsafeRawPointer(bitPattern: Int($0)) }
        guard let array = CFArrayCreate(kCFAllocatorDefault, &rawPointers, rawPointers.count, nil),
              let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [[CFString: Any]] else {
            return [:]
        }

        return descriptions.reduce(into: [:]) { result, description in
            guard let windowID = description[kCGWindowNumber] as? CGWindowID else {
                return
            }

            result[windowID] = description
        }
    }

    private static func frame(from description: [CFString: Any]) -> CGRect? {
        guard let bounds = description[kCGWindowBounds] as? NSDictionary else {
            return nil
        }

        return CGRect(dictionaryRepresentation: bounds)
    }

    private static func cgsFrame(for windowID: CGWindowID) -> CGRect? {
        var rect = CGRect.zero
        guard CGSGetScreenRectForWindow(CGSMainConnectionID(), windowID, &rect) == .success,
              !rect.isNull,
              !rect.isEmpty else {
            return nil
        }

        return rect
    }
}

private struct AccessibilityMenuBarItem {
    let ownerPID: pid_t
    let title: String
    let frame: CGRect
}

private enum AccessibilityMenuBarItemReader {
    static func items(for ownerPIDs: Set<pid_t>) -> [AccessibilityMenuBarItem] {
        guard AXIsProcessTrusted() else {
            return []
        }

        return ownerPIDs.flatMap(items(for:))
    }

    private static func items(for ownerPID: pid_t) -> [AccessibilityMenuBarItem] {
        let appElement = AXUIElementCreateApplication(ownerPID)
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBar = menuBarValue else {
            return []
        }

        return children(of: menuBar as! AXUIElement).compactMap { element in
            guard let title = title(of: element),
                  let frame = frame(of: element) else {
                return nil
            }

            return AccessibilityMenuBarItem(ownerPID: ownerPID, title: title, frame: frame)
        }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return []
        }

        return children
    }

    private static func title(of element: AXUIElement) -> String? {
        let attributes = [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            "AXHelp",
            "AXIdentifier",
            kAXValueAttribute,
        ]

        let candidates = attributes.compactMap { attribute in
            stringAttribute(attribute, of: element)
        }

        if let userFacingCandidate = candidates.first(where: { candidate in
            RealMenuBarItemSnapshot.userFacingTitle(candidate) != nil
        }) {
            return userFacingCandidate
        }

        if let childTitle = children(of: element).compactMap(title(of:)).first {
            return childTitle
        }

        return candidates.first { !$0.isEmpty }
    }

    private static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }
}

private extension Array where Element == AccessibilityMenuBarItem {
    func bestTitle(ownerPID: pid_t, frame: CGRect) -> String? {
        let match = self
            .filter { $0.ownerPID == ownerPID }
            .min { lhs, rhs in
                abs(lhs.frame.midX - frame.midX) < abs(rhs.frame.midX - frame.midX)
            }

        guard let match,
              abs(match.frame.midX - frame.midX) <= Swift.max(24, frame.width) else {
            return nil
        }

        return match.title
    }
}

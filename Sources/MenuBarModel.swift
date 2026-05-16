import AppKit
import Foundation

enum MenuBarItemVisibility: String, Codable, Equatable {
    case visible
    case hidden
}

enum MenuBarItemSection: String, Equatable {
    case visible
    case hidden
    case protected

    var displayTitle: String {
        switch self {
        case .visible: "Shown"
        case .hidden: "Hidden"
        case .protected: "Pinned"
        }
    }
}

enum MenuBarVisibilityPolicyMode: String, Codable, Equatable {
    case manual
    case keepOnlySelectedVisible
}

struct ManagedMenuBarItem: Identifiable, Equatable {
    let id: String
    let stableID: String
    let displayName: String
    let detail: String
    let sortX: Double
    let icon: NSImage?
    let section: MenuBarItemSection
    let preferredVisibility: MenuBarItemVisibility?
    let canBeHidden: Bool

    static func == (lhs: ManagedMenuBarItem, rhs: ManagedMenuBarItem) -> Bool {
        lhs.id == rhs.id
            && lhs.stableID == rhs.stableID
            && lhs.displayName == rhs.displayName
            && lhs.detail == rhs.detail
            && lhs.sortX == rhs.sortX
            && lhs.section == rhs.section
            && lhs.preferredVisibility == rhs.preferredVisibility
            && lhs.canBeHidden == rhs.canBeHidden
    }
}

struct MenuBarSettings: Codable, Equatable {
    var isCollapsed: Bool
    var hiddenWidth: Double
    var autoCollapseEnabled: Bool
    var autoCollapseDelay: Double
    var visibilityPolicyMode: MenuBarVisibilityPolicyMode
    var alwaysVisibleItemIDs: Set<String>
    var itemVisibilities: [String: MenuBarItemVisibility]

    static let defaults = MenuBarSettings(
        isCollapsed: true,
        hiddenWidth: 1_100,
        autoCollapseEnabled: true,
        autoCollapseDelay: 6,
        visibilityPolicyMode: .manual,
        alwaysVisibleItemIDs: [],
        itemVisibilities: [:]
    )

    init(
        isCollapsed: Bool,
        hiddenWidth: Double,
        autoCollapseEnabled: Bool,
        autoCollapseDelay: Double,
        visibilityPolicyMode: MenuBarVisibilityPolicyMode = .manual,
        alwaysVisibleItemIDs: Set<String> = [],
        itemVisibilities: [String: MenuBarItemVisibility] = [:]
    ) {
        self.isCollapsed = isCollapsed
        self.hiddenWidth = hiddenWidth
        self.autoCollapseEnabled = autoCollapseEnabled
        self.autoCollapseDelay = autoCollapseDelay
        self.visibilityPolicyMode = visibilityPolicyMode
        self.alwaysVisibleItemIDs = alwaysVisibleItemIDs
        self.itemVisibilities = itemVisibilities
    }

    func preferredVisibility(for stableID: String) -> MenuBarItemVisibility? {
        switch visibilityPolicyMode {
        case .manual:
            return itemVisibilities[stableID]
        case .keepOnlySelectedVisible:
            guard !alwaysVisibleItemIDs.isEmpty else {
                return nil
            }

            return alwaysVisibleItemIDs.contains(stableID) ? .visible : .hidden
        }
    }

    func sanitizedForLaunch() -> MenuBarSettings {
        var copy = self
        copy.hiddenWidth = MenuBarLayoutPolicy.clampedHiddenWidth(copy.hiddenWidth)
        copy.autoCollapseDelay = min(max(copy.autoCollapseDelay, 1), 30)
        copy.alwaysVisibleItemIDs = copy.alwaysVisibleItemIDs.filter { itemID in
            !itemID.isEmpty && !Self.referencesOpaqueMenuBarTitle(itemID)
        }
        copy.itemVisibilities = copy.itemVisibilities.filter { itemID, _ in
            !itemID.isEmpty && !Self.referencesOpaqueMenuBarTitle(itemID)
        }
        return copy
    }

    private static func referencesOpaqueMenuBarTitle(_ itemID: String) -> Bool {
        let opaqueTitleSegmentPatterns = [
            #":Item-\d+:"#,
            #":[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}:"#,
        ]

        return opaqueTitleSegmentPatterns.contains { pattern in
            itemID.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

enum MenuBarLayoutPolicy {
    static let minHiddenWidth = 300.0
    static let maxHiddenWidth = 1_400.0
    static let controlWidth = 30.0
    static let hiddenDividerCollapsedLength = 10_000.0

    static func clampedHiddenWidth(_ width: Double) -> Double {
        min(max(width.rounded(), minHiddenWidth), maxHiddenWidth)
    }

    static func targetHiddenSpan(for settings: MenuBarSettings) -> Double {
        settings.isCollapsed ? clampedHiddenWidth(settings.hiddenWidth) : 0
    }
}

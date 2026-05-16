import CoreGraphics
import Foundation

struct ManagedMenuBarItemIdentity: Equatable {
    let windowID: CGWindowID
    let stableID: String
    let displayName: String
}

enum MenuBarItemIdentityResolver {
    static func resolve(
        items: [RealMenuBarItemSnapshot],
        existingStableIDsByWindowID: [CGWindowID: String] = [:],
        stableIDForItem: (RealMenuBarItemSnapshot) -> String = { $0.stableID },
        displayNameForItem: (RealMenuBarItemSnapshot) -> String = { $0.displayName }
    ) -> [CGWindowID: ManagedMenuBarItemIdentity] {
        let sortedItems = items.sorted {
            if $0.frame.minX == $1.frame.minX {
                return $0.windowID < $1.windowID
            }

            return $0.frame.minX < $1.frame.minX
        }
        let duplicateGroups = Dictionary(grouping: sortedItems, by: stableIDForItem)
        var indexesByBaseStableID: [String: Int] = [:]

        return sortedItems.reduce(into: [:]) { result, item in
            let baseStableID = stableIDForItem(item)
            let baseDisplayName = displayNameForItem(item)
            let hasDuplicates = (duplicateGroups[baseStableID]?.count ?? 0) > 1

            guard hasDuplicates else {
                result[item.windowID] = ManagedMenuBarItemIdentity(
                    windowID: item.windowID,
                    stableID: existingStableIDsByWindowID[item.windowID] ?? baseStableID,
                    displayName: baseDisplayName
                )
                return
            }

            indexesByBaseStableID[baseStableID, default: 0] += 1
            let index = indexesByBaseStableID[baseStableID, default: 1]
            let stableID = existingStableIDsByWindowID[item.windowID]
                ?? "\(baseStableID)#window-\(item.windowID)-w\(Int(item.frame.width.rounded()))"
            result[item.windowID] = ManagedMenuBarItemIdentity(
                windowID: item.windowID,
                stableID: stableID,
                displayName: duplicateDisplayName(baseDisplayName, index: index)
            )
        }
    }

    private static func duplicateDisplayName(_ displayName: String, index: Int) -> String {
        return "\(displayName) #\(index)"
    }
}

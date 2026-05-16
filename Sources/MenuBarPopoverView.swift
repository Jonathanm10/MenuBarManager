import SwiftUI
import UniformTypeIdentifiers

struct MenuBarConfigurationView: View {
    @Bindable var store: MenuBarManagerStore
    @State private var targetedSection: MenuBarItemSection?

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Divider()

            ScrollView {
                content
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
            }

            Divider()

            footer
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 600, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            store.refreshMenuBarItems()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text("Menu bar layout")
                    .font(.system(size: 13, weight: .semibold))
                Text(layoutSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            collapseStateChip

            permissionButtons

            Button {
                store.refreshMenuBarItems()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isMovingMenuBarItem)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var layoutSummary: String {
        "\(store.visibleItemCount) shown · \(store.hiddenItemCount) hidden · \(store.protectedItemCount) pinned"
    }

    private var collapseStateChip: some View {
        let title = store.isCollapsed ? "Hidden" : "Expanded"
        let systemImage = store.isCollapsed ? "eye.slash" : "eye"
        return HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.secondary.opacity(0.12), in: Capsule())
        .help(store.isCollapsed ? "Hidden section is collapsed" : "Hidden section is showing")
    }

    @ViewBuilder
    private var permissionButtons: some View {
        if !store.screenCapturePreviewsAreEnabled {
            Button {
                store.requestScreenCapturePreviews()
            } label: {
                Label("Icon previews", systemImage: "camera.viewfinder")
            }
            .help("Grant Screen Recording so MenuBarManager can show the exact menu bar glyphs.")
            .disabled(store.isMovingMenuBarItem)
        }

        if !store.accessibilityLabelsAreEnabled {
            Button {
                store.requestAccessibilityLabels()
            } label: {
                Label("Better labels", systemImage: "text.viewfinder")
            }
            .help("Uses Accessibility labels to make generic menu bar items easier to recognize.")
            .disabled(store.isMovingMenuBarItem)
            .accessibilityIdentifier("ImproveItemRecognition")
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Drag menu bar items between lanes to arrange them. Saved choices replay on the next launch.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            searchField

            if let status = store.itemActionStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("ItemActionStatus")
            }

            lane(
                title: "Shown",
                subtitle: "\(store.visibleItemCount) visible",
                section: .visible,
                items: store.filteredVisibleMenuBarItems
            )

            lane(
                title: "Hidden",
                subtitle: "\(store.hiddenItemCount) behind MenuBarManager",
                section: .hidden,
                items: store.filteredHiddenMenuBarItems
            )

            lane(
                title: "Always hidden",
                subtitle: "\(store.protectedItemCount) pinned by macOS",
                section: .protected,
                items: store.filteredProtectedMenuBarItems
            )

            Divider()
                .padding(.vertical, 2)

            allItemsList
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search items", text: Binding(
                get: { store.itemSearchText },
                set: { store.itemSearchText = $0 }
            ))
            .textFieldStyle(.plain)
            .accessibilityIdentifier("ItemSearch")

            if !store.itemSearchText.isEmpty {
                Button {
                    store.itemSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Lane

    private func lane(
        title: String,
        subtitle: String,
        section: MenuBarItemSection,
        items: [ManagedMenuBarItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: sectionIconName(section))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            laneSurface(section: section, items: items)
        }
    }

    private func laneSurface(
        section: MenuBarItemSection,
        items: [ManagedMenuBarItem]
    ) -> some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if items.isEmpty {
                        Text(emptyMessage(for: section))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(minWidth: max(0, proxy.size.width), minHeight: 44)
                    } else {
                        HStack(spacing: 6) {
                            Spacer(minLength: 12)

                            ForEach(items) { item in
                                laneItem(item, in: section)
                            }

                            if section == .visible {
                                appControlMarker
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minWidth: max(0, proxy.size.width), minHeight: 44, alignment: .trailing)
                    }
                }
            }
        }
        .frame(height: 44)
        .clipped()
        .background(menuBarLaneBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    targetedSection == section ? Color.accentColor : Color.white.opacity(0.06),
                    lineWidth: targetedSection == section ? 2 : 0.5
                )
        )
        .onDrop(
            of: [UTType.plainText],
            isTargeted: sectionDropBinding(section),
            perform: { providers in
                guard section != .protected else {
                    return false
                }

                return handleDrop(providers, before: nil, in: section)
            }
        )
    }

    private var menuBarLaneBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(white: 0.18),
                Color(white: 0.10),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func emptyMessage(for section: MenuBarItemSection) -> String {
        switch section {
        case .visible:
            return "Drop items here to keep them in the menu bar"
        case .hidden:
            return "Drop items here to hide them"
        case .protected:
            return "No pinned items"
        }
    }

    private func laneItem(_ item: ManagedMenuBarItem, in section: MenuBarItemSection) -> some View {
        itemIcon(item, size: 22, style: .menuBar)
            .frame(width: 28, height: 30)
            .contentShape(Rectangle())
            .help(item.detail)
            .opacity(store.isMovingMenuBarItem ? 0.55 : 1)
            .onDrag {
                NSItemProvider(object: item.id as NSString)
            }
            .onDrop(
                of: [UTType.plainText],
                isTargeted: nil,
                perform: { providers in
                    guard section != .protected else {
                        return false
                    }

                    return handleDrop(providers, before: item, in: section)
                }
            )
            .disabled(store.isMovingMenuBarItem || !item.canBeHidden)
            .accessibilityLabel("\(item.displayName), \(section.displayTitle)")
    }

    private var appControlMarker: some View {
        Image(nsImage: StatusBarController.previewStatusBarIcon())
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 14)
            .frame(width: 28, height: 30)
            .foregroundStyle(.white.opacity(0.85))
            .help("MenuBarManager")
            .accessibilityLabel("MenuBarManager control")
    }

    // MARK: - All items list

    private var allItemsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("All items")
                    .font(.system(size: 13, weight: .semibold))

                Text("\(store.savedVisibilityRuleCount) saved rule\(store.savedVisibilityRuleCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    store.clearSavedItemVisibilityRules()
                } label: {
                    Label("Reset rules", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
                .disabled(store.savedVisibilityRuleCount == 0 || store.isMovingMenuBarItem)
            }

            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(store.filteredMenuBarItems) { item in
                    itemRow(item)
                }
            }
        }
    }

    private func itemRow(_ item: ManagedMenuBarItem) -> some View {
        HStack(spacing: 10) {
            itemIcon(item, size: 22, style: .detail)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if let ruleBadge = ruleBadgeText(for: item) {
                        badge(ruleBadge, tint: .orange)
                    }
                }

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            sectionTag(for: item.section)

            if item.canBeHidden {
                Toggle(isOn: Binding(
                    get: { item.section == .visible },
                    set: { store.moveMenuBarItem(item, to: $0 ? .visible : .hidden) }
                )) {
                    Text("Shown")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(store.isMovingMenuBarItem)
                .accessibilityLabel("Shown \(item.displayName)")
                .accessibilityIdentifier("Shown.\(item.stableID)")
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Pinned by macOS")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        )
        .onDrag {
            NSItemProvider(object: item.id as NSString)
        }
    }

    private func sectionTag(for section: MenuBarItemSection) -> some View {
        let title: String
        switch section {
        case .visible:
            title = "Shown"
        case .hidden:
            title = "Hidden"
        case .protected:
            title = "Pinned"
        }
        return Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.12), in: Capsule())
    }

    private func ruleBadgeText(for item: ManagedMenuBarItem) -> String? {
        guard let preferredVisibility = item.preferredVisibility,
              preferredVisibility != actualVisibility(for: item) else {
            return nil
        }

        return preferredVisibility == .visible ? "Rule: show" : "Rule: hide"
    }

    private func badge(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .lineLimit(1)
    }

    private func actualVisibility(for item: ManagedMenuBarItem) -> MenuBarItemVisibility? {
        switch item.section {
        case .visible:
            return .visible
        case .hidden:
            return .hidden
        case .protected:
            return nil
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { store.launchAtLoginEnabled },
                set: { store.setLaunchAtLoginEnabled($0) }
            )) {
                Text("Open at login")
                    .lineLimit(1)
            }
            .toggleStyle(.checkbox)

            if let error = store.lastLaunchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Item icon helper

    private enum ItemIconStyle {
        case menuBar
        case detail
    }

    private func itemIcon(_ item: ManagedMenuBarItem, size: CGFloat, style: ItemIconStyle) -> some View {
        Group {
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .padding(style == .menuBar ? 1 : 3)
            } else if let systemImage = fallbackSystemImageName(for: item) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.7, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(style == .menuBar ? Color.white.opacity(0.14) : Color.secondary.opacity(0.18))
                    Text(initials(for: item.displayName))
                        .font(.system(size: style == .menuBar ? 10 : 11, weight: .bold))
                }
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(style == .menuBar ? Color.white.opacity(0.85) : Color.primary)
        .accessibilityHidden(true)
    }

    private func sectionIconName(_ section: MenuBarItemSection) -> String {
        switch section {
        case .visible:
            return "eye"
        case .hidden:
            return "eye.slash"
        case .protected:
            return "lock"
        }
    }

    private func fallbackSystemImageName(for item: ManagedMenuBarItem) -> String? {
        let haystack = "\(item.displayName) \(item.detail)".lowercased()
        if haystack.contains("wi-fi") || haystack.contains("wifi") {
            return "wifi"
        }
        if haystack.contains("battery") {
            return "battery.100percent"
        }
        if haystack.contains("clock") || haystack.contains("date") {
            return "clock"
        }
        if haystack.contains("control center") || haystack.contains("bentobox") {
            return "switch.2"
        }
        if haystack.contains("focus") {
            return "moon"
        }
        if haystack.contains("now playing") || haystack.contains("music") {
            return "play.circle"
        }
        if haystack.contains("screen mirroring") {
            return "rectangle.on.rectangle"
        }
        if haystack.contains("keyboard") {
            return "keyboard"
        }
        if haystack.contains("siri") {
            return "sparkles"
        }
        return nil
    }

    private func sectionDropBinding(_ section: MenuBarItemSection) -> Binding<Bool> {
        Binding(
            get: { targetedSection == section },
            set: { isTargeted in
                targetedSection = isTargeted ? section : nil
            }
        )
    }

    private func handleDrop(
        _ providers: [NSItemProvider],
        before target: ManagedMenuBarItem?,
        in section: MenuBarItemSection
    ) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            let itemID: String?
            if let data = item as? Data {
                itemID = String(data: data, encoding: .utf8)
            } else if let string = item as? String {
                itemID = string
            } else if let string = item as? NSString {
                itemID = string as String
            } else {
                itemID = nil
            }

            guard let itemID else {
                return
            }

            Task { @MainActor in
                store.placeMenuBarItem(withID: itemID, before: target?.id, in: section)
            }
        }

        return true
    }

    private func initials(for name: String) -> String {
        let words = name
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(2)
        let letters = words.compactMap(\.first)
        guard !letters.isEmpty else {
            return "?"
        }

        return String(letters).uppercased()
    }
}

#Preview {
    MenuBarConfigurationView(
        store: MenuBarManagerStore(
            preferencesClient: MenuBarPreferencesClient(defaults: .standard),
            launchAtLoginClient: LaunchAtLoginClient()
        )
    )
}

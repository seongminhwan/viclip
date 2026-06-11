import SwiftUI
import AppKit
import Combine

struct PopupWindowView: View {
    @ObservedObject private var clipboardMonitor = ClipboardMonitor.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = AppLanguageManager.shared
    @StateObject private var vimEngine = VIMEngine()
    @StateObject private var sequentialPaster = SequentialPaster()

    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""  // Debounced for database queries
    @State private var searchTask: Task<Void, Never>? = nil  // For cancelling old search tasks
    @State private var selectedIndex: Int = 0
    @State private var showFavoritesOnly: Bool = false
    @State private var selectedTypeFilter: ContentTypeFilter = .all
    @State private var isCommandMode: Bool = false  // Command mode (:)
    @State private var commandMenuIndex: Int = 0  // Selected command in menu
    @State private var isPositionMode: Bool = false  // Position mode (p)
    @State private var positionAnchorItem: ClipboardItem? = nil  // The item we're positioning around
    @State private var isTypeFilterMode: Bool = false  // Type filter mode (F)
    @State private var typeFilterIndex: Int = 0  // Selected filter in dropdown
    @State private var isPreviewMode: Bool = false  // Full preview mode (v)
    @State private var previewingItem: ClipboardItem? = nil  // Item being previewed
    @State private var previewOCRResult: String? = nil  // OCR extracted text
    @State private var isPerformingOCR: Bool = false  // OCR in progress
    @State private var previewScrollOffset: CGFloat = 0  // Scroll position
    @State private var showCopiedFeedback: Bool = false  // Copy feedback indicator
    @FocusState private var isSearchFocused: Bool  // SEARCH mode when true, NORMAL when false
    @State private var searchModeEnterCount: Int = 0  // Track Enter presses in SEARCH mode: first=exit, second=paste

    // Tag Manager state
    @ObservedObject private var tagService = TagService.shared
    @State private var isTagPanelOpen: Bool = false
    @State private var isTagPanelFocused: Bool = false  // true = focus on tags, false = focus on history
    @State private var selectedTagIndex: Int = 0
    @State private var lastSelectedTagIndex: Int = 0
    @State private var isCreatingTag: Bool = false
    @State private var isRenamingTag: Bool = false
    @State private var editingTagName: String = ""
    @State private var isDeletingTagConfirm: Bool = false  // Delete confirmation mode
    @State private var tagToDelete: Tag? = nil

    // Tag Association Popup (for item tagging)
    @State private var isTagAssociationPopupOpen: Bool = false
    @State private var tagAssociationPopupIndex: Int = 0
    @State private var isCreatingTagInPopup: Bool = false
    @State private var newTagNameInPopup: String = ""
    @State private var itemTagIds: Set<String> = []  // Tags for current item
    @FocusState private var isPopupTagInputFocused: Bool

    // Pinned items (items under pinned tags, with PIN_ prefix)
    @State private var pinnedItems: [ClipboardItem] = []
    @State private var pinnedItemTagIds: [UUID: Set<String>] = [:]

    // PIN area visibility toggle (CMD+P)
    @State private var isPinAreaVisible: Bool = true

    // Selected pinned tag IDs for filtering PIN area (independent from TagService.selectedTagIds)
    @State private var selectedPinnedTagIds: Set<String> = []

    // Tag bar scroll offset (for Ctrl+[/] scrolling)
    @State private var tagBarScrollOffset: CGFloat = 0

    // Async preview loading to prevent UI lag with large content
    @State private var previewText: String? = nil
    @State private var isLoadingPreview: Bool = false
    @State private var previewItemId: UUID? = nil

    // Help panel for showing keyboard shortcuts
    @State private var isHelpPanelOpen: Bool = false
    @State private var helpScrollIndex: Int = 0

    // Advanced filter state
    @State private var isAdvancedFilterOpen: Bool = false
    @State private var advancedFilter: FilterQuery = FilterQuery()

    // Rename/alias state for inline editing
    @State private var isRenamingItem: Bool = false
    @State private var renamingItemId: String? = nil  // Using displayId for unique row identification
    @State private var editingItemAlias: String = ""
    @FocusState private var isRenameInputFocused: Bool

    // GOTO Mode State
    @State private var isGotoMode: Bool = false
    @State private var visibleIndices: Set<Int> = []
    @State private var gotoRefreshTrigger: Int = 0  // Incremented to force row refresh in GOTO mode

    // Mouse click detection state (for manual double-click detection)
    @State private var lastClickedItemId: String? = nil
    @State private var lastClickTime: Date = .distantPast
    @State private var isNavigatingViaKeyboard: Bool = false  // Flag to distinguish keyboard vs mouse navigation
    @State private var scrollToTopTrigger: UUID = UUID()  // Trigger to scroll list to top

    @Environment(\.colorScheme) private var colorScheme

    enum ContentTypeFilter: String, CaseIterable {
        case all = "All Types"
        case text = "Text"
        case image = "Image"
        case file = "File"

        var displayName: String {
            switch self {
            case .all: return L10n.t("contentType.all", "All Types")
            case .text: return L10n.t("contentType.text", "Text")
            case .image: return L10n.t("contentType.image", "Image")
            case .file: return L10n.t("contentType.file", "File")
            }
        }
    }

    // Command menu options
    struct CommandOption: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let shortcut: String
        let action: () -> Void
    }

    private var commandOptions: [CommandOption] {
        guard let item = selectedItem else { return [] }
        return [
            CommandOption(icon: "doc.on.doc", title: L10n.t("popup.paste", "Paste"), shortcut: "⏎") {
                clipboardMonitor.paste(item: item)
            },
            CommandOption(icon: "location", title: L10n.t("keybinding.position", "Locate in Timeline"), shortcut: "p") {
                enterPositionMode(for: item)
            },
            CommandOption(
                icon: item.isFavorite ? "star.fill" : "star",
                title: item.isFavorite
                    ? L10n.t("popup.removeFavorite", "Remove from Favorites")
                    : L10n.t("popup.addFavorite", "Add to Favorites"),
                shortcut: "f"
            ) {
                clipboardMonitor.toggleFavorite(item: item)
            },
            CommandOption(icon: "plus.square.on.square", title: L10n.t("keybinding.addToQueue", "Add to Paste Queue"), shortcut: "q") {
                sequentialPaster.addToQueue(item)
            },
            CommandOption(icon: "trash", title: L10n.t("popup.delete", "Delete"), shortcut: "d") {
                clipboardMonitor.delete(item: item)
            }
        ]
    }

    private var filteredPinnedItems: [ClipboardItem] {
        // If PIN area is hidden, return empty
        guard isPinAreaVisible else { return [] }

        var filteredPinned = pinnedItems

        // Filter by selected pinned tags
        // - Empty selection = show all
        // - All selected = show all
        // - Partial selection = filter by selected tags (but always include directly pinned items)
        let allTagIds = Set(tagService.tags.map { $0.id })
        let isAllSelected = !selectedPinnedTagIds.isEmpty && selectedPinnedTagIds == allTagIds

        if !selectedPinnedTagIds.isEmpty && !isAllSelected {
            filteredPinned = filteredPinned.filter { item in
                // Always include directly pinned items
                if item.isDirectPinned {
                    return true
                }
                // Check if item belongs to any of the selected tags
                let itemTagIds = pinnedItemTagIds[item.originalId] ?? []
                return !itemTagIds.isDisjoint(with: selectedPinnedTagIds)
            }
        }

        // Apply search filter to pinned items (includes alias)
        if !searchText.isEmpty {
            let parsedSearch = parseSearchQuery(searchText)
            if let query = parsedSearch.query {
                filteredPinned = filteredPinned.filter { item in
                    SearchMatchHighlighter.containsMatch(
                        in: item.displayText,
                        query: query,
                        isRegex: parsedSearch.isRegex
                    )
                }
            }
        }

        // Apply type filter to pinned items
        switch selectedTypeFilter {
        case .all:
            break
        case .text:
            filteredPinned = filteredPinned.filter {
                if case .text = $0.content { return true }
                if case .richText = $0.content { return true }
                return false
            }
        case .image:
            filteredPinned = filteredPinned.filter {
                if case .image = $0.content { return true }
                return false
            }
        case .file:
            filteredPinned = filteredPinned.filter {
                if case .fileURL = $0.content { return true }
                return false
            }
        }

        return filteredPinned
    }

    private var filteredItems: [ClipboardItem] {
        // If in position mode, show items around the anchor
        if isPositionMode, let anchor = positionAnchorItem {
            return getItemsAroundAnchor(anchor)
        }

        // Items now include search results (unified interface)
        // Type filtering is done at the SQL level via contentType parameter
        var items = clipboardMonitor.items

        // Filter favorites only
        if showFavoritesOnly {
            items = items.filter { $0.isFavorite }
        }

        // Prepend filtered pinned items
        return filteredPinnedItems + items
    }

    private func getItemsAroundAnchor(_ anchor: ClipboardItem) -> [ClipboardItem] {
        let allItems = clipboardMonitor.items
        guard let anchorIndex = allItems.firstIndex(where: { $0.id == anchor.id }) else {
            return allItems
        }

        let startIndex = max(0, anchorIndex - 20)
        let endIndex = min(allItems.count, anchorIndex + 21)

        return Array(allItems[startIndex..<endIndex])
    }

    private var selectedItem: ClipboardItem? {
        guard let item = filteredItems[safe: selectedIndex] else { return nil }
        return clipboardMonitor.cachedFullItem(for: item) ?? item
    }

    private var theme: ThemeColors {
        ThemeColors.forScheme(colorScheme)
    }

    private var currentMode: String {
        if isCommandMode {
            return "COMMAND"
        } else if isPositionMode {
            return "POSITION"
        } else if isSearchFocused {
            return "SEARCH"
        } else if isTagPanelOpen {
            return "TAG"
        } else {
            return "NORMAL"
        }
    }

    /// Display mode - shows "FILTERED" when filter is active, otherwise same as currentMode
    private var displayMode: String {
        // Show FILTERED when search or advanced filter is active
        if currentMode == "NORMAL" {
            if !searchText.isEmpty || clipboardMonitor.activeFilter?.isActive == true {
                return "FILTERED"
            }
        }
        return currentMode
    }

    /// NORMAL mode means search is not focused - all VIM commands work
    private var isNormalMode: Bool {
        !isSearchFocused &&
        !isCommandMode &&
        !isRenamingItem &&
        !isCreatingTag &&
        !isRenamingTag &&
        !isCreatingTagInPopup &&
        !isTypeFilterMode &&
        !isPreviewMode &&
        !isHelpPanelOpen &&
        !isTagAssociationPopupOpen &&
        !isAdvancedFilterOpen
    }

    private var modeColor: Color {
        switch displayMode {
        case "COMMAND": return .purple
        case "POSITION": return .cyan
        case "SEARCH": return .orange
        case "TAG": return .teal
        case "FILTERED": return .yellow
        default: return .green
        }
    }

    private func localizedModeName(_ mode: String) -> String {
        switch mode {
        case "COMMAND": return L10n.t("mode.command", "COMMAND")
        case "POSITION": return L10n.t("mode.position", "POSITION")
        case "SEARCH": return L10n.t("mode.search", "SEARCH")
        case "TAG": return L10n.t("mode.tag", "TAG")
        case "FILTERED": return L10n.t("mode.filtered", "FILTERED")
        default: return L10n.t("mode.normal", "NORMAL")
        }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Tag Manager Panel (animated)
                if isTagPanelOpen {
                    TagManagerPanel(
                        tagService: tagService,
                        selectedTagIndex: $selectedTagIndex,
                        isCreatingTag: $isCreatingTag,
                        isRenamingTag: $isRenamingTag,
                        editingTagName: $editingTagName,
                        isFocusedOnTags: $isTagPanelFocused,
                        isDeletingTagConfirm: $isDeletingTagConfirm,
                        tagToDelete: $tagToDelete,
                        theme: theme,
                        onConfirmFilter: {
                            // Move focus to history list
                            isTagPanelFocused = false
                            lastSelectedTagIndex = selectedTagIndex
                        },
                        onCancel: {
                            closeTagPanel()
                        }
                    )
                    .frame(width: 200)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Main content
                VStack(spacing: 0) {
                    // Header with search
                    headerView

                    Divider()

                    // Main content - split view
                    HSplitView {
                        // Left panel - list
                        leftListPanel
                            .frame(minWidth: 280, maxWidth: 350)

                        // Right panel - preview & info
                        rightPreviewPanel
                            .frame(minWidth: 300)
                    }

                    Divider()

                    // Footer
                    footerView
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isTagPanelOpen)

            // Command mode overlay
            if isCommandMode {
                commandModeOverlay
            }

            // Type filter mode overlay
            if isTypeFilterMode {
                typeFilterOverlay
            }

            // Preview mode overlay
            if isPreviewMode, let item = previewingItem {
                previewOverlay(for: item)
            }

            // Help panel overlay (must be after preview to appear on top)
            if isHelpPanelOpen {
                helpPanelOverlay
            }

            // Tag association popup overlay
            if isTagAssociationPopupOpen {
                tagAssociationPopupOverlay
            }

            // Advanced filter overlay
            if isAdvancedFilterOpen {
                advancedFilterOverlay
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(KeyEventHandlingView(onKeyDown: handleKeyDown))
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            // Reset state when window is shown
            selectedIndex = 0
            searchText = ""
            debouncedSearchText = ""
            isCommandMode = false
            isPositionMode = false
            isTypeFilterMode = false
            isPreviewMode = false
            isHelpPanelOpen = false
            isTagAssociationPopupOpen = false
            isAdvancedFilterOpen = false
            selectedTypeFilter = .all  // Reset type filter
            scrollToTopTrigger = UUID()  // Trigger scroll to top
            vimEngine.resetState()
            // Start in NORMAL mode (search not focused)
            isSearchFocused = false
            // Reload items to get fresh data
            clipboardMonitor.setSearchQuery(nil, tagIds: nil, contentType: nil, isRegex: false)
        }
        .onAppear {
            selectedIndex = 0
            vimEngine.resetState()
            // Start in NORMAL mode
            isSearchFocused = false
            // Load pinned items
            loadPinnedItems()
        }
        .onChange(of: isTagPanelOpen) { newValue in
            // Notify window to resize
            NotificationCenter.default.post(
                name: .tagPanelStateChanged,
                object: nil,
                userInfo: ["isOpen": newValue]
            )
        }
        .onChange(of: searchText) { newValue in
            // Cancel previous search task
            searchTask?.cancel()

            // Debounce search: wait 300ms after typing stops before querying database
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms

                // Check if cancelled
                guard !Task.isCancelled else { return }

                // Only update if searchText hasn't changed
                if searchText == newValue {
                    await MainActor.run {
                        debouncedSearchText = newValue
                        // Detect /pattern/ regex syntax
                        let (query, isRegex) = parseSearchQuery(newValue)
                        // Use unified interface to set search query with current tag and type filter
                        let tagIds = Array(tagService.selectedTagIds)
                        clipboardMonitor.setSearchQuery(
                            query,
                            tagIds: tagIds.isEmpty ? nil : tagIds,
                            contentType: contentTypeString(for: selectedTypeFilter),
                            isRegex: isRegex
                        )
                        selectedIndex = 0  // Reset selection on new search
                    }
                }
            }
        }
        .onChange(of: tagService.selectedTagIds) { newValue in
            // Real-time tag filtering: reload items when tag selection changes
            let tagIds = Array(newValue)
            let (query, isRegex) = parseSearchQuery(searchText)
            clipboardMonitor.setSearchQuery(
                query,
                tagIds: tagIds.isEmpty ? nil : tagIds,
                contentType: contentTypeString(for: selectedTypeFilter),
                isRegex: isRegex
            )
            selectedIndex = 0  // Reset selection
        }
        .onChange(of: selectedTypeFilter) { newValue in
            // Push type filtering to SQL level
            let tagIds = Array(tagService.selectedTagIds)
            let (query, isRegex) = parseSearchQuery(searchText)
            clipboardMonitor.setSearchQuery(
                query,
                tagIds: tagIds.isEmpty ? nil : tagIds,
                contentType: contentTypeString(for: newValue),
                isRegex: isRegex
            )
            selectedIndex = 0
        }
    }

    // MARK: - Command Mode Overlay

    private var commandModeOverlay: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Command menu
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "command")
                        .foregroundColor(theme.accent)
                    Text(L10n.t("popup.actions", "Actions"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(L10n.t("popup.escToClose", "ESC to close"))
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(theme.tertiaryBackground)

                Divider()

                // Options
                VStack(spacing: 2) {
                    ForEach(Array(commandOptions.enumerated()), id: \.element.id) { index, option in
                        HStack {
                            Image(systemName: option.icon)
                                .frame(width: 20)
                                .foregroundColor(index == commandMenuIndex ? .white : theme.accent)

                            Text(option.title)
                                .font(.system(size: 13))

                            Spacer()

                            Text(option.shortcut)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(index == commandMenuIndex ? .white.opacity(0.7) : theme.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(index == commandMenuIndex ? Color.white.opacity(0.2) : theme.tertiaryBackground)
                                .cornerRadius(4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(index == commandMenuIndex ? theme.accent : Color.clear)
                        .foregroundColor(index == commandMenuIndex ? .white : theme.text)
                        .cornerRadius(6)
                    }
                }
                .padding(8)
            }
            .frame(width: 300)
            .background(theme.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }

    // MARK: - Advanced Filter Overlay

    private var advancedFilterOverlay: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isAdvancedFilterOpen = false
                }

            // Filter panel
            AdvancedFilterView(
                filter: $advancedFilter,
                isPresented: $isAdvancedFilterOpen
            )
        }
    }

    // MARK: - Active Filter Indicator

    private var filterIndicator: some View {
        Group {
            if clipboardMonitor.activeFilter?.isActive == true {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    Text(L10n.t("popup.filtered", "Filtered"))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.accent)
                .cornerRadius(4)
                .onTapGesture {
                    isAdvancedFilterOpen = true
                }
            }
        }
    }

    private var helpPanelOverlay: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Help content
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.accent.opacity(0.18))
                            .frame(width: 30, height: 30)
                        Image(systemName: "keyboard")
                            .foregroundColor(theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("help.title", "Keyboard Shortcuts"))
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.t("help.featureGuide", "Feature Guide"))
                            .font(.system(size: 11))
                            .foregroundColor(theme.secondaryText)
                    }

                    Spacer()

                    Text(currentContextName)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.accent.opacity(0.2))
                        .cornerRadius(4)
                }
                .foregroundColor(theme.text)
                .padding(12)
                .background(theme.tertiaryBackground)

                Divider()

                // Shortcuts list with j/k navigation
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(currentHelpRows) { row in
                                if let title = row.sectionTitle {
                                    Text(title)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(theme.secondaryText)
                                        .textCase(.uppercase)
                                        .padding(.horizontal, 14)
                                        .padding(.top, row.isFirstSection ? 8 : 14)
                                        .padding(.bottom, 3)
                                } else if let shortcut = row.shortcut, let index = row.shortcutIndex {
                                    helpShortcutRow(shortcut, isSelected: index == helpScrollIndex)
                                        .id("help-shortcut-\(index)")
                                }
                            }
                        }
                        .padding(.bottom, 10)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: helpScrollIndex) { newIndex in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("help-shortcut-\(newIndex)", anchor: .center)
                        }
                    }
                }

                Divider()

                // Footer
                HStack {
                    KeyHint(key: L10n.t("help.footerNavigate", "j/k or ↑↓"), action: L10n.t("help.footerScroll", "scroll"), theme: theme)
                    Spacer()
                    KeyHint(key: L10n.t("help.footerClose", "?/ESC"), action: L10n.t("help.footerCloseAction", "close"), theme: theme)
                }
                .font(.system(size: 10))
                .foregroundColor(theme.secondaryText)
                .padding(12)
            }
            .frame(width: 520)
            .background(theme.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }

    private func helpShortcutRow(_ shortcut: ShortcutInfo, isSelected: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(shortcut.key)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(isSelected ? .white : theme.accent)
                .frame(width: 104, alignment: .leading)

            Text(shortcut.description)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .white : theme.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? theme.accent : Color.clear)
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }

    private var currentContextName: String {
        if isPreviewMode, let item = previewingItem {
            switch item.content {
            case .image: return L10n.t("context.imagePreview", "IMAGE PREVIEW")
            case .text: return L10n.t("context.textPreview", "TEXT PREVIEW")
            case .richText: return L10n.t("context.textPreview", "TEXT PREVIEW")
            case .fileURL: return L10n.t("context.filePreview", "FILE PREVIEW")
            }
        } else if isTagPanelOpen && isTagPanelFocused {
            return L10n.t("context.tagPanel", "TAG PANEL")
        } else if isTagPanelOpen && !isTagPanelFocused {
            return L10n.t("context.tagHistory", "TAG HISTORY")
        } else if isCommandMode {
            return L10n.t("context.command", "COMMAND")
        } else if isSearchFocused {
            return L10n.t("context.search", "SEARCH")
        } else if !searchText.isEmpty {
            return L10n.t("context.filtered", "FILTERED")
        } else if isGotoMode {
            return L10n.t("context.goto", "GOTO")
        } else {
            return L10n.t("context.normal", "NORMAL")
        }
    }

    private struct ShortcutInfo: Identifiable {
        let key: String
        let description: String
        var id: String { "\(key)|\(description)" }
    }

    private struct HelpSection: Identifiable {
        let title: String
        let shortcuts: [ShortcutInfo]

        var id: String { title }
    }

    private struct HelpDisplayRow: Identifiable {
        let id: String
        let sectionTitle: String?
        let shortcut: ShortcutInfo?
        let shortcutIndex: Int?
        let isFirstSection: Bool
    }

    private var currentContextShortcuts: [ShortcutInfo] {
        currentHelpSections.flatMap(\.shortcuts)
    }

    private var currentHelpRows: [HelpDisplayRow] {
        var rows: [HelpDisplayRow] = []
        var shortcutIndex = 0

        for (sectionIndex, section) in currentHelpSections.enumerated() {
            rows.append(HelpDisplayRow(
                id: "section-\(sectionIndex)-\(section.id)",
                sectionTitle: section.title,
                shortcut: nil,
                shortcutIndex: nil,
                isFirstSection: sectionIndex == 0
            ))

            for shortcut in section.shortcuts {
                rows.append(HelpDisplayRow(
                    id: "shortcut-\(shortcutIndex)-\(shortcut.id)",
                    sectionTitle: nil,
                    shortcut: shortcut,
                    shortcutIndex: shortcutIndex,
                    isFirstSection: false
                ))
                shortcutIndex += 1
            }
        }

        return rows
    }

    private var currentHelpSections: [HelpSection] {
        var sections = [HelpSection(
            title: L10n.t("help.section.currentMode", "Current Mode"),
            shortcuts: contextSpecificShortcuts
        )]

        sections.append(HelpSection(
            title: L10n.t("help.section.navigation", "Navigation"),
            shortcuts: navigationShortcuts
        ))

        sections.append(HelpSection(
            title: L10n.t("help.section.searchFilter", "Search & Filter"),
            shortcuts: searchAndFilterShortcuts
        ))

        sections.append(HelpSection(
            title: L10n.t("help.section.pinTags", "Pins & Tags"),
            shortcuts: pinAndTagShortcuts
        ))

        sections.append(HelpSection(
            title: L10n.t("help.section.preview", "Preview"),
            shortcuts: previewShortcuts
        ))

        sections.append(HelpSection(
            title: L10n.t("help.section.actionsQueue", "Actions & Queue"),
            shortcuts: actionAndQueueShortcuts
        ))

        return sections.filter { !$0.shortcuts.isEmpty }
    }

    private func shortcut(_ key: String, _ descriptionKey: String, _ fallback: String) -> ShortcutInfo {
        ShortcutInfo(key: key, description: L10n.t(descriptionKey, fallback))
    }

    private var contextSpecificShortcuts: [ShortcutInfo] {
        let kb = keyBindingManager

        // Preview mode shortcuts
        if isPreviewMode, let item = previewingItem {
            switch item.content {
            case .image:
                return [
                    shortcut(kb.binding(for: .previewOCR).displayString, "help.desc.previewOCR", "Extract image text with OCR"),
                    shortcut(kb.binding(for: .previewCopy).displayString, "help.desc.previewCopy", "Copy preview text or OCR result"),
                    shortcut(kb.binding(for: .previewOpenExternal).displayString, "help.desc.openExternal", "Open in external app or Finder"),
                    shortcut(kb.binding(for: .escape).displayString + " / v", "help.desc.previewClose", "Close preview"),
                    shortcut("?", "help.desc.help", "Show this help"),
                ]
            case .text, .richText:
                return [
                    shortcut(kb.binding(for: .previewScrollDown).displayString + " / " + kb.binding(for: .previewScrollUp).displayString, "help.desc.previewScroll", "Scroll text preview"),
                    shortcut(kb.binding(for: .previewHalfPageDown).displayString + " / " + kb.binding(for: .previewHalfPageUp).displayString, "help.desc.previewHalfPage", "Half-page preview scroll"),
                    shortcut(kb.binding(for: .previewCopy).displayString, "help.desc.previewCopy", "Copy preview text or OCR result"),
                    shortcut(kb.binding(for: .previewOpenExternal).displayString, "help.desc.openExternal", "Open in external app or Finder"),
                    shortcut(kb.binding(for: .escape).displayString + " / v", "help.desc.previewClose", "Close preview"),
                    shortcut("?", "help.desc.help", "Show this help"),
                ]
            case .fileURL:
                return [
                    shortcut(kb.binding(for: .previewOpenExternal).displayString, "help.desc.openExternal", "Open in external app or Finder"),
                    shortcut(kb.binding(for: .escape).displayString + " / v", "help.desc.previewClose", "Close preview"),
                    shortcut("?", "help.desc.help", "Show this help"),
                ]
            }
        } else if isTagPanelOpen && isTagPanelFocused {
            return [
                shortcut("j / ↓", "help.desc.moveDown", "Move down"),
                shortcut("k / ↑", "help.desc.moveUp", "Move up"),
                shortcut("Space", "help.desc.tagSelect", "Toggle tag selection"),
                shortcut("n", "help.desc.tagCreate", "Create a tag"),
                shortcut("r", "help.desc.tagRename", "Rename selected tag"),
                shortcut("d", "help.desc.tagDelete", "Delete selected tag"),
                shortcut("⇧P", "help.desc.tagPin", "Pin selected tag"),
                shortcut("l / ⏎", "help.desc.tagFocusHistory", "Focus history results"),
                shortcut("⎋", "help.desc.tagBack", "Return to tag list / close panel"),
            ]
        } else if isTagPanelOpen && !isTagPanelFocused {
            return [
                shortcut("j / ↓", "help.desc.moveDown", "Move down"),
                shortcut("k / ↑", "help.desc.moveUp", "Move up"),
                shortcut("⏎", "help.desc.pasteSelected", "Paste selected item"),
                shortcut("t", "help.desc.tagItem", "Edit tags on current item"),
                shortcut("h / ⎋", "help.desc.tagBack", "Return to tag list / close panel"),
            ]
        } else if isSearchFocused {
            return [
                shortcut("j / ↓", "help.desc.moveDown", "Move down"),
                shortcut("k / ↑", "help.desc.moveUp", "Move up"),
                shortcut("⏎ (1st)", "help.desc.searchEnterFirst", "First Enter exits search mode"),
                shortcut("⏎ (2nd)", "help.desc.searchEnterSecond", "Second Enter pastes selected item"),
                shortcut("⌘1-9", "help.desc.searchQuickPaste", "Paste one of the visible results"),
                shortcut("⌃P", "help.desc.searchLocate", "Exit search and locate item in full history"),
                shortcut("⎋", "help.desc.cancel", "Cancel / close"),
            ]
        } else if !searchText.isEmpty {
            return [
                shortcut(kb.binding(for: .moveDown).displayString + " / ↓", "help.desc.moveDown", "Move down"),
                shortcut(kb.binding(for: .moveUp).displayString + " / ↑", "help.desc.moveUp", "Move up"),
                shortcut(kb.binding(for: .paste).displayString, "help.desc.pasteSelected", "Paste selected item"),
                shortcut(kb.binding(for: .position).displayString, "help.desc.locateTimeline", "Locate search/pinned item in timeline"),
                shortcut(kb.binding(for: .search).displayString, "help.desc.searchFocus", "Focus search input"),
                shortcut(kb.binding(for: .escape).displayString, "help.desc.clearFiltered", "Clear search/filter before closing"),
            ]
        } else if isGotoMode {
            // GOTO mode shortcuts
            return [
                shortcut("1-9, a-z", "help.desc.gotoSelect", "Paste visible item"),
                shortcut("g / G", "help.desc.gotoTopBottom", "Top / bottom in GOTO mode"),
                shortcut("j / k", "help.desc.moveDown", "Move down"),
                shortcut("⌃D / ⌃U", "help.desc.halfPageHistory", "Half-page history scroll"),
                shortcut("⌘D / ⌘U", "help.desc.previewHalfPage", "Half-page preview scroll"),
                shortcut("⎋", "help.desc.cancel", "Cancel / close"),
            ]
        } else {
            // NORMAL mode - use dynamic bindings from KeyBindingManager
            return [
                shortcut(kb.binding(for: .moveDown).displayString + " / ↓", "help.desc.moveDown", "Move down"),
                shortcut(kb.binding(for: .moveUp).displayString + " / ↑", "help.desc.moveUp", "Move up"),
                shortcut("⌃D / ⌃U", "help.desc.halfPageHistory", "Half-page history scroll"),
                shortcut(kb.binding(for: .paste).displayString, "help.desc.pasteSelected", "Paste selected item"),
                shortcut("⌘⏎", "help.desc.pastePlain", "Paste as plain text"),
                shortcut("g", "help.desc.gotoMode", "Show visible-item quick keys"),
                shortcut(kb.binding(for: .search).displayString, "help.desc.searchFocus", "Focus search input"),
                shortcut("?", "help.desc.help", "Show this help"),
            ]
        }
    }

    private var navigationShortcuts: [ShortcutInfo] {
        let kb = keyBindingManager
        return [
            shortcut(kb.binding(for: .moveDown).displayString + " / " + kb.binding(for: .moveUp).displayString, "help.desc.moveDown", "Move down"),
            shortcut("⌃D / ⌃U", "help.desc.halfPageHistory", "Half-page history scroll"),
            shortcut("gg / G", "help.desc.toTopBottom", "Jump to top / bottom"),
            shortcut("g", "help.desc.gotoMode", "Show visible-item quick keys"),
            shortcut("1-9, a-z", "help.desc.gotoSelect", "Paste visible item"),
        ]
    }

    private var searchAndFilterShortcuts: [ShortcutInfo] {
        let kb = keyBindingManager
        return [
            shortcut(kb.binding(for: .search).displayString, "help.desc.searchFocus", "Focus search input"),
            shortcut("/pattern/", "help.desc.regexSearch", "Use /pattern/ for regex search"),
            shortcut("⌘F", "help.desc.advancedFilter", "Open advanced filter panel"),
            shortcut(kb.binding(for: .filterByType).displayString, "help.desc.typeFilter", "Filter by content type"),
            shortcut(kb.binding(for: .position).displayString, "help.desc.locateTimeline", "Locate search/pinned item in timeline"),
            shortcut("ESC", "help.desc.clearFiltered", "Clear search/filter before closing"),
        ]
    }

    private var pinAndTagShortcuts: [ShortcutInfo] {
        [
            shortcut("⇧P", "help.desc.togglePin", "Pin or unpin current item"),
            shortcut("⌘P", "help.desc.togglePinArea", "Show or hide pinned area"),
            shortcut("⌘1-9 / ⌘a-z", "help.desc.filterPinnedTags", "Filter pinned area by tag"),
            shortcut("⌘0", "help.desc.toggleAllPinnedTags", "Select or clear all pinned tag filters"),
            shortcut("⌘[ / ⌘]", "help.desc.scrollTagBar", "Scroll the pinned tag bar"),
            shortcut("t", "help.desc.tagItem", "Edit tags on current item"),
            shortcut("⇧T", "help.desc.openTagPanel", "Open tag manager panel"),
        ]
    }

    private var previewShortcuts: [ShortcutInfo] {
        let kb = keyBindingManager
        return [
            shortcut(kb.binding(for: .quickPreview).displayString, "help.desc.previewItem", "Preview selected item"),
            shortcut(kb.binding(for: .previewOpenExternal).displayString, "help.desc.openExternal", "Open in external app or Finder"),
            shortcut("j/k, ⌘D/⌘U", "help.desc.previewScroll", "Scroll text preview"),
            shortcut(kb.binding(for: .previewCopy).displayString, "help.desc.previewCopy", "Copy preview text or OCR result"),
            shortcut(kb.binding(for: .previewOCR).displayString, "help.desc.previewOCR", "Extract image text with OCR"),
        ]
    }

    private var actionAndQueueShortcuts: [ShortcutInfo] {
        let kb = keyBindingManager
        return [
            shortcut(kb.binding(for: .commandMenu).displayString, "help.desc.commandMenu", "Open action menu"),
            shortcut(kb.binding(for: .addToQueue).displayString, "help.desc.queue", "Add selected item to paste queue"),
            shortcut("⌘⌥V", "help.desc.pasteQueueNext", "Paste next queued item"),
            shortcut("R", "help.desc.renameAlias", "Rename / set alias"),
            shortcut(kb.binding(for: .favorite).displayString, "help.desc.favorite", "Toggle favorite"),
            shortcut(kb.binding(for: .delete).displayString, "help.desc.delete", "Delete selected item"),
        ]
    }

    private var typeFilterOverlay: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Filter dropdown
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(theme.accent)
                    Text(L10n.t("popup.filterByType", "Filter by Type"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(L10n.t("popup.escToClose", "ESC to close"))
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(theme.tertiaryBackground)

                Divider()

                // Filter options
                VStack(spacing: 2) {
                    ForEach(Array(ContentTypeFilter.allCases.enumerated()), id: \.element) { index, filter in
                        HStack {
                            Image(systemName: iconForFilter(filter))
                                .frame(width: 20)
                                .foregroundColor(index == typeFilterIndex ? .white : theme.accent)

                            Text(filter.displayName)
                                .font(.system(size: 13))

                            Spacer()

                            if filter == selectedTypeFilter {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(index == typeFilterIndex ? .white : theme.accent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(index == typeFilterIndex ? theme.accent : Color.clear)
                        .foregroundColor(index == typeFilterIndex ? .white : theme.text)
                        .cornerRadius(6)
                    }
                }
                .padding(8)

                Divider()

                // Footer hints
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("↑↓/jk")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(theme.tertiaryBackground)
                            .cornerRadius(3)
                        Text(L10n.t("popup.navigate", "Navigate"))
                            .font(.system(size: 10))
                    }

                    HStack(spacing: 4) {
                        Text("⏎/␣")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(theme.tertiaryBackground)
                            .cornerRadius(3)
                        Text(L10n.t("popup.select", "Select"))
                            .font(.system(size: 10))
                    }
                }
                .foregroundColor(theme.secondaryText)
                .padding(12)
            }
            .frame(width: 260)
            .background(theme.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }

    private func iconForFilter(_ filter: ContentTypeFilter) -> String {
        switch filter {
        case .all: return "square.grid.2x2"
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "folder"
        }
    }

    // MARK: - Tag Association Popup

    private var tagAssociationPopupOverlay: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    closeTagAssociationPopup()
                }

            // Popup
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundColor(theme.accent)
                    Text(L10n.t("popup.tagItem", "Tag Item"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(L10n.t("popup.escToClose", "ESC to close"))
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(theme.tertiaryBackground)

                Divider()

                // Tag list with checkboxes
                ScrollView {
                    VStack(spacing: 2) {
                        if tagService.tags.isEmpty {
                            Text(L10n.t("popup.noTagsCreate", "No tags yet. Press 'n' to create one."))
                                .font(.system(size: 12))
                                .foregroundColor(theme.secondaryText)
                                .padding(16)
                        } else {
                            ForEach(Array(tagService.tags.enumerated()), id: \.element.id) { index, tag in
                                HStack {
                                    // Checkbox
                                    Image(systemName: itemTagIds.contains(tag.id) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 14))
                                        .foregroundColor(itemTagIds.contains(tag.id) ? theme.accent : theme.secondaryText)

                                    // Tag name
                                    Text(tag.name)
                                        .font(.system(size: 13))

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(index == tagAssociationPopupIndex ? theme.accent.opacity(0.3) : Color.clear)
                                .foregroundColor(theme.text)
                                .cornerRadius(6)
                            }
                        }

                        // New tag input
                        if isCreatingTagInPopup {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(theme.accent)

                                TextField(L10n.t("popup.newTagName", "New tag name..."), text: $newTagNameInPopup)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .focused($isPopupTagInputFocused)
                                    .onSubmit {
                                        createTagInPopup()
                                    }

                                Button(action: { cancelTagCreationInPopup() }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(theme.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(theme.tertiaryBackground)
                            .cornerRadius(6)
                            .onAppear {
                                isPopupTagInputFocused = true
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 200)

                Divider()

                // Footer hints
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("j/k")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(theme.tertiaryBackground)
                            .cornerRadius(3)
                        Text(L10n.t("popup.nav", "nav"))
                            .font(.system(size: 10))
                    }

                    HStack(spacing: 4) {
                        Text("␣")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(theme.tertiaryBackground)
                            .cornerRadius(3)
                        Text(L10n.t("popup.toggle", "toggle"))
                            .font(.system(size: 10))
                    }

                    HStack(spacing: 4) {
                        Text("n")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(theme.tertiaryBackground)
                            .cornerRadius(3)
                        Text(L10n.t("popup.new", "new"))
                            .font(.system(size: 10))
                    }
                }
                .foregroundColor(theme.secondaryText)
                .padding(12)
            }
            .frame(width: 280)
            .background(theme.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }

    // MARK: - Keyboard Handling

    private var keyBindingManager: KeyBindingManager { KeyBindingManager.shared }

    private func handleKeyDown(with event: NSEvent) -> Bool {
        let keyCode = event.keyCode

        if isHelpPanelOpen {
            return handleHelpPanelKey(keyCode: keyCode, event: event)
        }

        // GOTO Mode Handling
        if isGotoMode {
            if keyCode == 44 && event.modifierFlags.contains(.shift) {
                isHelpPanelOpen = true
                helpScrollIndex = 0
                return true
            }

            if keyCode == 53 { // ESC
                isGotoMode = false
                return true
            }

            // Handle shortcuts
            if let char = event.charactersIgnoringModifiers?.first {
                let isControlDown = event.modifierFlags.contains(.control)
                let isCommandDown = event.modifierFlags.contains(.command)

                // j: Move down one item
                if char == "j" && !isControlDown && !isCommandDown {
                    isNavigatingViaKeyboard = true
                    gotoRefreshTrigger += 1  // Force refresh shortcuts
                    if selectedIndex < filteredItems.count - 1 {
                        selectedIndex += 1
                    }
                    return true
                }

                // k: Move up one item
                if char == "k" && !isControlDown && !isCommandDown {
                    isNavigatingViaKeyboard = true
                    gotoRefreshTrigger += 1  // Force refresh shortcuts
                    if selectedIndex > 0 {
                        selectedIndex -= 1
                    }
                    return true
                }

                // Ctrl+D: Move down 5 items (half page)
                if char == "d" && isControlDown {
                    isNavigatingViaKeyboard = true
                    gotoRefreshTrigger += 1  // Force refresh shortcuts
                    selectedIndex = min(selectedIndex + 5, filteredItems.count - 1)
                    return true
                }

                // Ctrl+U: Move up 5 items (half page)
                if char == "u" && isControlDown {
                    isNavigatingViaKeyboard = true
                    gotoRefreshTrigger += 1  // Force refresh shortcuts
                    selectedIndex = max(selectedIndex - 5, 0)
                    return true
                }

                // Cmd+D/U: Preview scroll - pass through
                if (char == "d" || char == "u") && isCommandDown {
                    previewScrollOffset += (char == "d" ? 200 : -200)
                    return true
                }

                let shortcuts = "123456789abcdefhilmnopqrstvwxyzABCDEFHIJKLMNOPQRSTUVWXYZ"

                // 'g': Scroll to Top
                if char == "g" && !event.modifierFlags.contains(.shift) {
                    isNavigatingViaKeyboard = true
                    selectedIndex = 0
                    isGotoMode = false
                    return true
                }

                // 'G': Scroll to Bottom
                if char == "G" || (char == "g" && event.modifierFlags.contains(.shift)) {
                    isNavigatingViaKeyboard = true
                    selectedIndex = max(0, filteredItems.count - 1)
                    isGotoMode = false
                    return true
                }

                // Shortcut Selection - only for visible items
                if let indexStr = shortcuts.firstIndex(of: char) {
                    let offset = shortcuts.distance(from: shortcuts.startIndex, to: indexStr)
                    if let minVisible = visibleIndices.min(), let maxVisible = visibleIndices.max() {
                        let targetIndex = minVisible + offset
                        // Only paste if target is within visible range
                        if targetIndex >= minVisible && targetIndex <= maxVisible && targetIndex < filteredItems.count {
                            let item = filteredItems[targetIndex]
                            clipboardMonitor.paste(item: item)
                            isGotoMode = false
                            return true
                        }
                    }
                }
            }
            return true // Consume other keys in GOTO mode
        }

        // Toggle GOTO Mode with 'g' (in Normal Mode)
        if keyCode == 5 && isNormalMode && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
            isGotoMode = true
            return true
        }

        // Help panel handling - ? or ESC to close, j/k to scroll
        if isHelpPanelOpen {
            if keyCode == 53 || (keyCode == 44 && event.modifierFlags.contains(.shift)) {
                // ESC or ? again closes help
                isHelpPanelOpen = false
                helpScrollIndex = 0
                return true
            }
            // j or Down - scroll down
            if keyCode == 38 || keyCode == 125 {
                let maxIndex = currentContextShortcuts.count - 1
                if helpScrollIndex < maxIndex {
                    helpScrollIndex += 1
                }
                return true
            }
            // k or Up - scroll up
            if keyCode == 40 || keyCode == 126 {
                if helpScrollIndex > 0 {
                    helpScrollIndex -= 1
                }
                return true
            }
            // Any other key closes help
            isHelpPanelOpen = false
            helpScrollIndex = 0
            return true
        }

        // ? key (Shift + /) opens help panel - NOT in SEARCH mode (allow typing ?)
        if keyCode == 44 && event.modifierFlags.contains(.shift) && !isSearchFocused && !isCreatingTag && !isRenamingTag && !isCreatingTagInPopup {
            isHelpPanelOpen = true
            helpScrollIndex = 0
            return true
        }

        // Advanced filter panel handling - ESC to close
        if isAdvancedFilterOpen {
            if keyCode == 53 {  // ESC
                isAdvancedFilterOpen = false
                return true
            }
            // Let the panel handle other keys
            return false
        }

        // ⌘F to open advanced filter (only in NORMAL mode)
        if keyCode == 3 && event.modifierFlags.contains(.command) && !isSearchFocused && !isPreviewMode && !isCommandMode && !isTypeFilterMode {
            isAdvancedFilterOpen = true
            return true
        }

        // Preview mode handling
        if isPreviewMode {
            let kb = keyBindingManager

            // ESC or v to close
            if keyCode == 53 || keyCode == 9 {
                exitPreviewMode()
                return true
            }

            // ? to open help (shift + /)
            if keyCode == 44 && event.modifierFlags.contains(.shift) {
                isHelpPanelOpen = true
                helpScrollIndex = 0
                return true
            }

            // Handle based on content type
            if let item = previewingItem {
                switch item.content {
                case .image:
                    // o for OCR (not open external for images)
                    if kb.matches(event, command: .previewOCR) && !isPerformingOCR {
                        performPreviewOCR(for: item)
                        return true
                    }
                    // ⌘C to copy OCR result
                    if kb.matches(event, command: .previewCopy) {
                        copyPreviewContent()
                        return true
                    }

                case .text, .richText:
                    // j/k for scrolling
                    if kb.matches(event, command: .previewScrollDown) {
                        scrollPreview(by: 40)
                        return true
                    }
                    if kb.matches(event, command: .previewScrollUp) {
                        scrollPreview(by: -40)
                        return true
                    }
                    // ⌃D/⌃U for half-page scroll
                    if kb.matches(event, command: .previewHalfPageDown) {
                        scrollPreview(by: 200)
                        return true
                    }
                    if kb.matches(event, command: .previewHalfPageUp) {
                        scrollPreview(by: -200)
                        return true
                    }
                    // ⌘C to copy content
                    if kb.matches(event, command: .previewCopy) {
                        copyPreviewContent()
                        return true
                    }
                    // o to open in external app
                    if kb.matches(event, command: .previewOpenExternal) {
                        openInExternalApp(item)
                        exitPreviewMode()
                        return true
                    }

                case .fileURL:
                    // o to open in Finder
                    if kb.matches(event, command: .previewOpenExternal) {
                        openInExternalApp(item)
                        exitPreviewMode()
                        return true
                    }
                }
            }

            return true  // Consume all keys in preview mode
        }

        // Type filter mode handling
        if isTypeFilterMode {
            return handleTypeFilterModeKey(keyCode: keyCode, event: event)
        }

        // Tag association popup handling
        if isTagAssociationPopupOpen {
            return handleTagAssociationPopupKey(keyCode: keyCode, event: event)
        }

        // Command mode handling
        if isCommandMode {
            return handleCommandModeKey(keyCode: keyCode)
        }

        // Tag panel mode handling (when open and focused on tags) - HIGHEST PRIORITY
        if isTagPanelOpen && isTagPanelFocused && !isCreatingTag && !isRenamingTag {
            if handleTagPanelKey(keyCode: keyCode, event: event) {
                return true
            }
        }

        // Arrow keys always work (even in SEARCH mode) - but NOT when Tag panel is focused
        // This allows navigating search results without Esc
        if !isTagPanelFocused, let arrowCommand = keyBindingManager.isArrowKey(event) {
            switch arrowCommand {
            case .moveDown: moveDown(); return true
            case .moveUp: moveUp(); return true
            default: break
            }
        }

        // Tab/Shift+Tab for quick navigation in SEARCH mode
        if keyCode == 48 {  // Tab key
            if event.modifierFlags.contains(.shift) {
                moveUp()
            } else {
                moveDown()
            }
            return true
        }

        // SEARCH mode: Ctrl+P exits search and locates item in NORMAL mode
        if isSearchFocused && keyCode == 35 && event.modifierFlags.contains(.control) {
            if let item = selectedItem {
                // Exit search mode
                isSearchFocused = false
                searchText = ""
                clipboardMonitor.loadFirstPage()  // Reset to first page

                // Find and select the original item in NORMAL mode
                let targetId = item.originalId
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let index = self.filteredItems.firstIndex(where: { $0.id == targetId }) {
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                            self.selectedIndex = index
                        }
                    }
                }
                return true
            }
        }

        // SEARCH Mode: Handle CMD+D/U scrolling and CMD+1..9 selection
        if isSearchFocused {
            let kb = keyBindingManager

            // Ctrl+D/U scrolling (consistent with NORMAL mode)
            // Uses configured keybindings (default is Ctrl+D/U)
            if kb.matches(event, command: .historyHalfPageDown) {
                 scrollHistoryByHalfPage(direction: .down)
                 return true
            }
            if kb.matches(event, command: .historyHalfPageUp) {
                 scrollHistoryByHalfPage(direction: .up)
                 return true
            }

            // CMD+1..9 Selection
            // Check for Command modifier (without Control/Option to avoid conflicts)
            if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) && !event.modifierFlags.contains(.option) {
                 if let chars = event.charactersIgnoringModifiers, let char = chars.first, "123456789".contains(char) {
                     // Reverse lookup index from visibleIndices
                     // Logic must match getShortcutChar sorting
                     let sortedVisible = visibleIndices.sorted()
                     // char '1' -> index 0 (1-based index)
                     if let digit = Int(String(char)), digit > 0 {
                         let targetOffset = digit - 1
                         if targetOffset < sortedVisible.count {
                             let targetIndex = sortedVisible[targetOffset]
                             // Paste the item
                             if let item = filteredItems[safe: targetIndex] {
                                 clipboardMonitor.paste(item: item)
                                 return true
                             }
                         }
                     }
                 }
            }
        }

        // SEARCH mode: only handle Escape, Tab, and Ctrl+P, let text field handle everything else
        if isSearchFocused && keyCode != 53 && keyCode != 48 {
            // Only intercept Ctrl+P
            if !(keyCode == 35 && event.modifierFlags.contains(.control)) {
                return false
            }
        }

        // Tag input mode: similarly, only handle Escape
        if (isCreatingTag || isRenamingTag) && keyCode != 53 {
            return false
        }

        // Rename mode: handle Enter/Escape, let text field handle other keys
        if isRenamingItem {
            if keyCode == 36 {  // Enter to confirm
                confirmRename()
                return true
            }
            if keyCode == 53 {  // Escape to cancel
                cancelRename()
                return true
            }
            // Let text field handle other keys
            return false
        }

        // R key for rename (keyCode 15) - only in NORMAL mode
        if keyCode == 15 && isNormalMode && !isTagPanelFocused && !isSearchFocused {
            if let item = selectedItem {
                isRenamingItem = true
                renamingItemId = item.displayId  // Use displayId for unique row identification
                editingItemAlias = item.alias ?? item.displayText
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isRenameInputFocused = true
                }
                return true
            }
        }

        // Ctrl+D/U for history list half-page scroll (only in NORMAL mode)
        if !isSearchFocused && !isTagPanelFocused {
            let kb = keyBindingManager
            if kb.matches(event, command: .historyHalfPageDown) {
                scrollHistoryByHalfPage(direction: .down)
                return true
            }
            if kb.matches(event, command: .historyHalfPageUp) {
                scrollHistoryByHalfPage(direction: .up)
                return true
            }

            // Cmd+D/U for preview panel half-page scroll (works in NORMAL mode)
            if kb.matches(event, command: .previewHalfPageDown) {
                scrollPreview(by: 200)
                return true
            }
            if kb.matches(event, command: .previewHalfPageUp) {
                scrollPreview(by: -200)
                return true
            }
        }

        // MARK: - PIN Area Keyboard Shortcuts

        // CMD+P to toggle PIN area visibility
        if keyCode == 35 && event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) && isNormalMode {
            isPinAreaVisible.toggle()
            // Clear tag selection when hiding
            if !isPinAreaVisible {
                selectedPinnedTagIds.removeAll()
                tagBarScrollOffset = 0
            }
            return true
        }

        // CMD+0-9 and CMD+a-z for tag selection (only when PIN area is visible)
        let hasCommand = event.modifierFlags.contains(.command)
        let hasControl = event.modifierFlags.contains(.control)
        let hasOption = event.modifierFlags.contains(.option)

        // CMD+key for tag selection (only when PIN area is visible)
        if hasCommand && !hasControl && !hasOption && isPinAreaVisible && isNormalMode {
            let keyCode = event.keyCode

            // CMD+0: Toggle all tags (keyCode 29)
            if keyCode == 29 {
                toggleAllPinnedTags()
                return true
            }

            // CMD+1-9: Select tags 0-8 (keyCodes: 1=18, 2=19, 3=20, 4=21, 5=23, 6=22, 7=26, 8=28, 9=25)
            let numberKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
            if let digit = numberKeyCodes[keyCode] {
                let index = digit - 1
                if index < tagService.tags.count {
                    let tag = tagService.tags[index]
                    togglePinnedTagSelection(tag.id)
                    return true
                }
            }

            // CMD+a-z: Select tags 9-34
            if let char = event.charactersIgnoringModifiers?.first, char >= "a" && char <= "z" {
                let letterIndex = Int(char.asciiValue! - Character("a").asciiValue!)
                let index = 9 + letterIndex  // a=9, b=10, etc.
                if index < tagService.tags.count {
                    let tag = tagService.tags[index]
                    togglePinnedTagSelection(tag.id)
                    return true
                }
            }

            // CMD+[ : Scroll tag bar left (keyCode 33)
            if keyCode == 33 {
                tagBarScrollOffset = max(0, tagBarScrollOffset - 5)
                return true
            }

            // CMD+] : Scroll tag bar right (keyCode 30)
            if keyCode == 30 {
                tagBarScrollOffset = min(CGFloat(max(0, tagService.tags.count - 1)), tagBarScrollOffset + 5)
                return true
            }
        }

        // Enter key - paste selected (only in NORMAL mode, not SEARCH)
        if keyCode == 36 && !isSearchFocused {
            if let item = selectedItem {
                clipboardMonitor.paste(item: item)
            }
            return true
        }

        // Number keys for quick select - DISABLED (use GOTO mode instead)
        // if !isSearchFocused, let num = keyBindingManager.quickSelectNumber(event) {
        //     let index = num - 1
        //     if index < filteredItems.count {
        //         selectedIndex = index
        //         if let item = selectedItem {
        //             clipboardMonitor.paste(item: item)
        //         }
        //         return true
        //     }
        // }

        // Get command from key binding
        if let command = keyBindingManager.command(for: event, vimEngine: vimEngine) {
            return executeCommand(command)
        }

        // Escape or h key handling
        if keyCode == 53 || keyCode == 4 { // ESC or h
            // Tag panel ESC/h handling hierarchy
            if isTagPanelOpen {
                if isCreatingTag || isRenamingTag {
                    // Cancel tag editing (only for ESC)
                    if keyCode == 53 {
                        isCreatingTag = false
                        isRenamingTag = false
                        editingTagName = ""
                        return true
                    }
                }
                if !isTagPanelFocused {
                    // Focus is on history, return to tag list
                    isTagPanelFocused = true
                    selectedTagIndex = lastSelectedTagIndex
                    return true
                }
                // Focus is on tags
                if keyCode == 53 {
                    // ESC: close panel
                    closeTagPanel()
                    return true
                }
                // h key ignored when focus on tags
                return true
            }

            // Not in tag panel mode - only handle ESC
            if keyCode == 53 {
                if isSearchFocused {
                    isSearchFocused = false
                    return true
                }
                if isPositionMode {
                    exitPositionMode()
                    return true
                }
                // If in FILTERED state (search or filter active), clear first before closing
                if displayMode == "FILTERED" {
                    // Clear search text
                    if !searchText.isEmpty {
                        searchText = ""
                        debouncedSearchText = ""
                        clipboardMonitor.loadFirstPage()
                    }
                    // Clear advanced filter
                    if clipboardMonitor.activeFilter?.isActive == true {
                        advancedFilter.reset()
                        clipboardMonitor.setAdvancedFilter(nil)
                    }
                    return true
                }
                // In NORMAL mode with no special modes - close popup
                print("DEBUG: ESC in NORMAL mode, calling closePopup()")
                AppDelegate.shared?.closePopup()
                return true
            }
        }

        // Shift+T to toggle tag panel (only in NORMAL mode)
        if keyCode == 17 && event.modifierFlags.contains(.shift) && isNormalMode {
            toggleTagPanel()
            return true
        }

        // Shift+P to toggle pin (in tag panel: pin current tag, in history: pin current item)
        if keyCode == 35 && event.modifierFlags.contains(.shift) && isNormalMode {
            if isTagPanelFocused && selectedTagIndex < tagService.tags.count {
                // Pin/unpin the currently selected tag
                let tag = tagService.tags[selectedTagIndex]
                tagService.togglePin(id: tag.id)
                loadPinnedItems()
                return true
            } else if !isTagPanelFocused, let item = selectedItem {
                // Pin/unpin the currently selected history item

                // Determine boundaries
                let pinnedCount = filteredPinnedItems.count
                let isPinnedSection = selectedIndex < pinnedCount

                if isPinnedSection {
                    // Pinned Section: Allow toggle (Unpin)
                    clipboardMonitor.togglePin(item: item)
                    loadPinnedItems()
                    // Selection stays at same index (next item shifts up)
                } else {
                    // History Section
                    if item.isDirectPinned {
                        // Already pinned - enforce "Pin once" rule
                        NSSound.beep()
                    } else {
                        // Not pinned - Pin it
                        let countBefore = filteredItems.count

                        clipboardMonitor.togglePin(item: item)
                        loadPinnedItems()

                        // Move selection +1: +1 for new pinned item at top
                        // This keeps the selection on the SAME item (which is now shifted down by 1)
                        selectedIndex = min(selectedIndex + 1, countBefore)
                    }
                }
                return true
            }
            return true
        }

        // 't' key (without shift) to open tag association popup for current item
        if keyCode == 17 && !event.modifierFlags.contains(.shift) && isNormalMode && !isTagPanelFocused {
            if selectedItem != nil {
                openTagAssociationPopup()
                return true
            }
        }

        return false
    }

    private func handleHelpPanelKey(keyCode: UInt16, event: NSEvent) -> Bool {
        if keyCode == 53 || (keyCode == 44 && event.modifierFlags.contains(.shift)) {
            isHelpPanelOpen = false
            helpScrollIndex = 0
            return true
        }

        if keyCode == 38 || keyCode == 125 {
            let maxIndex = max(0, currentContextShortcuts.count - 1)
            helpScrollIndex = min(helpScrollIndex + 1, maxIndex)
            return true
        }

        if keyCode == 40 || keyCode == 126 {
            helpScrollIndex = max(helpScrollIndex - 1, 0)
            return true
        }

        isHelpPanelOpen = false
        helpScrollIndex = 0
        return true
    }

    private func executeCommand(_ command: KeyBindingManager.Command) -> Bool {
        switch command {
        case .moveUp:
            moveUp()
            return true

        case .moveDown:
            moveDown()
            return true

        case .moveToTop:
            selectedIndex = 0
            return true

        case .moveToBottom:
            selectedIndex = max(0, filteredItems.count - 1)
            return true

        case .paste:
            if let item = selectedItem {
                clipboardMonitor.paste(item: item)
                return true
            }

        case .pasteAsPlainText:
            if let item = selectedItem {
                clipboardMonitor.pasteAsPlainText(item: item)
                return true
            }

        case .delete:
            if let item = selectedItem {
                clipboardMonitor.delete(item: item)
                return true
            }

        case .favorite:
            if let item = selectedItem {
                clipboardMonitor.toggleFavorite(item: item)
                return true
            }

        case .search:
            searchModeEnterCount = 0  // Reset counter when entering SEARCH mode
            isSearchFocused = true
            return true

        case .commandMenu:
            enterCommandMode()
            return true

        case .position:
            // P key: works when searchText is not empty (filtered content) or for pinned items
            // Clears search and locates item in full history
            if !isSearchFocused, let item = selectedItem, (!searchText.isEmpty || item.isPinnedItem) {
                let targetId = item.originalId

                // Clear search first
                searchText = ""

                // Use loadToItem to load data up to the target item's position
                // This handles cases where the item is beyond the currently loaded page
                DispatchQueue.main.async {
                    if let historyIndex = self.clipboardMonitor.loadToItem(itemId: targetId) {
                        // Calculate the actual index including the pinned section
                        let pinnedCount = self.filteredPinnedItems.count
                        let actualIndex = pinnedCount + historyIndex

                        self.isNavigatingViaKeyboard = true  // Trigger scroll to visible
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                            self.selectedIndex = actualIndex
                        }
                    }
                }
                return true
            }

        case .addToQueue:
            if let item = selectedItem {
                sequentialPaster.addToQueue(item)
                return true
            }

        case .quickPreview:
            if let item = selectedItem {
                previewItem(item)
                return true
            }

        case .filterByType:
            enterTypeFilterMode()
            return true

        case .escape:
            // Tag panel ESC handling hierarchy
            if isTagPanelOpen {
                if isCreatingTag || isRenamingTag {
                    // Cancel tag editing
                    isCreatingTag = false
                    isRenamingTag = false
                    editingTagName = ""
                    return true
                }
                if !isTagPanelFocused {
                    // Focus is on history, return to tag list
                    isTagPanelFocused = true
                    selectedTagIndex = lastSelectedTagIndex
                    return true
                }
                // Focus is on tags, close panel
                closeTagPanel()
                return true
            }

            if isTypeFilterMode {
                exitTypeFilterMode()
                return true
            }
            if isSearchFocused {
                isSearchFocused = false
                return true
            }
            if isPositionMode {
                exitPositionMode()
                return true
            }
            // If in FILTERED state (search or filter active), clear first before closing
            if displayMode == "FILTERED" {
                // Clear search text
                if !searchText.isEmpty {
                    searchText = ""
                    debouncedSearchText = ""
                    clipboardMonitor.loadFirstPage()
                }
                // Clear advanced filter
                if clipboardMonitor.activeFilter?.isActive == true {
                    advancedFilter.reset()
                    clipboardMonitor.setAdvancedFilter(nil)
                }
                return true
            }
            // In NORMAL mode with no special modes - close popup
            AppDelegate.shared?.closePopup()
            return true

        // Preview mode commands - handled elsewhere, just return false here
        case .previewOCR, .previewCopy, .previewScrollUp, .previewScrollDown,
             .previewHalfPageUp, .previewHalfPageDown, .previewOpenExternal,
             .historyHalfPageUp, .historyHalfPageDown:
            return false

        // Advanced filter - handled by keyboard shortcut directly
        case .advancedFilter:
            isAdvancedFilterOpen = true
            return true
        }

        return false
    }

    // MARK: - Type Filter Mode

    /// Parse search text to detect /pattern/ regex syntax
    /// Returns (query, isRegex) - if text matches /pattern/, strips slashes and returns isRegex=true
    private func parseSearchQuery(_ text: String) -> (query: String?, isRegex: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, false) }

        // Detect /pattern/ syntax (must start and end with /, with content between)
        if trimmed.count >= 3,
           trimmed.hasPrefix("/"),
           trimmed.hasSuffix("/") {
            let pattern = String(trimmed.dropFirst().dropLast())
            if !pattern.isEmpty {
                return (pattern, true)
            }
        }

        return (trimmed, false)
    }

    private func highlightedSearchText(_ text: String) -> AttributedString {
        let (query, isRegex) = parseSearchQuery(searchText)
        return SearchMatchHighlighter.attributedString(
            text,
            query: query,
            isRegex: isRegex
        )
    }

    private func highlightedSearchText(_ attributedString: NSAttributedString, maxMatches: Int = 200) -> NSAttributedString {
        let (query, isRegex) = parseSearchQuery(searchText)
        return SearchMatchHighlighter.apply(
            to: attributedString,
            query: query,
            isRegex: isRegex,
            maxMatches: maxMatches
        )
    }

    /// Map UI type filter to DB content_type string for SQL-level filtering
    /// Returns nil for .all (no filtering)
    private func contentTypeString(for filter: ContentTypeFilter) -> String? {
        switch filter {
        case .all: return nil
        case .text: return "text"       // DB also has "richText" - handled in query via IN clause
        case .image: return "image"
        case .file: return "fileURL"
        }
    }

    private func enterTypeFilterMode() {
        isTypeFilterMode = true
        typeFilterIndex = ContentTypeFilter.allCases.firstIndex(of: selectedTypeFilter) ?? 0
    }

    private func exitTypeFilterMode() {
        isTypeFilterMode = false
    }

    private func confirmTypeFilter() {
        let filters = ContentTypeFilter.allCases
        if typeFilterIndex < filters.count {
            selectedTypeFilter = filters[typeFilterIndex]
        }
        exitTypeFilterMode()
    }

    private func handleTypeFilterModeKey(keyCode: UInt16, event: NSEvent) -> Bool {
        let filterCount = ContentTypeFilter.allCases.count

        switch keyCode {
        case 53: // Escape
            exitTypeFilterMode()
            return true

        case 36, 49: // Enter or Space
            confirmTypeFilter()
            return true

        case 125, 38, 48: // Down, j, or Tab
            typeFilterIndex = (typeFilterIndex + 1) % filterCount
            return true

        case 126, 40: // Up or k
            typeFilterIndex = (typeFilterIndex - 1 + filterCount) % filterCount
            return true

        default:
            // Shift+Tab for up
            if keyCode == 48 && event.modifierFlags.contains(.shift) {
                typeFilterIndex = (typeFilterIndex - 1 + filterCount) % filterCount
                return true
            }
        }

        return false
    }

    // MARK: - Tag Panel Mode

    private func toggleTagPanel() {
        withAnimation {
            if isTagPanelOpen {
                closeTagPanel()
            } else {
                openTagPanel()
            }
        }
    }

    private func openTagPanel() {
        tagService.loadTags()
        isTagPanelOpen = true
        isTagPanelFocused = true
        // Clamp to valid range
        let tagCount = tagService.tags.count
        if tagCount > 0 {
            selectedTagIndex = min(lastSelectedTagIndex, tagCount - 1)
        } else {
            selectedTagIndex = 0
        }
    }

    private func closeTagPanel() {
        // Clear tag selection to remove filter when panel closes
        tagService.clearSelection()

        isTagPanelOpen = false
        isTagPanelFocused = false
        isCreatingTag = false
        isRenamingTag = false
        editingTagName = ""
    }

    /// Load items that belong to pinned tags or are directly pinned, using single query
    private func loadPinnedItems() {
        do {
            let pinnedResults = try DatabaseManager.shared.fetchAllPinnedItems()
            pinnedItems = pinnedResults.compactMap { result -> ClipboardItem? in
                guard var item = result.item.toClipboardItemSummary() else { return nil }
                // Set virtual ID for unique identification and pin type for color
                item.virtualId = "PIN_\(item.id.uuidString)"
                switch result.pinType {
                case .direct:
                    item.pinType = .direct
                case .tag:
                    item.pinType = .tag
                case .both:
                    item.pinType = .both
                }
                return item
            }
            let itemIds = pinnedItems.map { $0.originalId.uuidString }
            let tagIdsByItemId = try DatabaseManager.shared.fetchTagIdsForItems(itemIds: itemIds)
            pinnedItemTagIds = tagIdsByItemId.reduce(into: [:]) { result, entry in
                if let uuid = UUID(uuidString: entry.key) {
                    result[uuid] = entry.value
                }
            }
        } catch {
            print("Error loading pinned items: \(error)")
            pinnedItems = []
            pinnedItemTagIds = [:]
        }
    }

    // MARK: - Rename/Alias Methods

    private func confirmRename() {
        guard let displayId = renamingItemId else {
            cancelRename()
            return
        }

        // Extract original UUID from displayId (may be "PIN_<uuid>" or just "<uuid>")
        let uuidString = displayId.hasPrefix("PIN_") ? String(displayId.dropFirst(4)) : displayId
        guard let itemId = UUID(uuidString: uuidString) else {
            cancelRename()
            return
        }

        // Trim whitespace and determine if alias should be cleared
        let trimmedAlias = editingItemAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliasToSet: String? = trimmedAlias.isEmpty ? nil : trimmedAlias

        // Update via ClipboardMonitor
        clipboardMonitor.setAlias(itemId: itemId, alias: aliasToSet)

        // Refresh pinned items to update aliases immediately
        loadPinnedItems()

        // Reset state
        cancelRename()
    }

    private func cancelRename() {
        isRenamingItem = false
        renamingItemId = nil
        editingItemAlias = ""
        isRenameInputFocused = false
    }

    private func startRename(item: ClipboardItem) {
        renamingItemId = item.displayId  // Use displayId for unique row identification
        isRenamingItem = true
        editingItemAlias = item.alias ?? ""
        isRenameInputFocused = true
    }

    private func handleTagPanelKey(keyCode: UInt16, event: NSEvent) -> Bool {
        let tagCount = tagService.tags.count

        // Handle delete confirmation mode first
        if isDeletingTagConfirm {
            switch keyCode {
            case 16: // y - yes, delete with cascade
                if let tag = tagToDelete {
                    tagService.deleteTag(id: tag.id, cascadeDeleteItems: true)
                    // Update selection index
                    if selectedTagIndex >= tagService.tags.count {
                        selectedTagIndex = max(0, tagService.tags.count - 1)
                    }
                }
                isDeletingTagConfirm = false
                tagToDelete = nil
                return true

            case 45, 36, 53: // n, Enter, or ESC - no, just delete tag
                if let tag = tagToDelete {
                    tagService.deleteTag(id: tag.id, cascadeDeleteItems: false)
                    if selectedTagIndex >= tagService.tags.count {
                        selectedTagIndex = max(0, tagService.tags.count - 1)
                    }
                }
                isDeletingTagConfirm = false
                tagToDelete = nil
                return true

            default:
                return true  // Block other keys during confirmation
            }
        }

        switch keyCode {
        case 38, 125: // j or Down - move down in tag list
            if tagCount > 0 {
                selectedTagIndex = (selectedTagIndex + 1) % tagCount
            }
            return true

        case 40, 126: // k or Up - move up in tag list
            if tagCount > 0 {
                selectedTagIndex = (selectedTagIndex - 1 + tagCount) % tagCount
            }
            return true

        case 49: // Space - toggle tag selection
            if selectedTagIndex < tagCount {
                let tag = tagService.tags[selectedTagIndex]
                tagService.toggleTagSelection(id: tag.id)
            }
            return true

        case 36, 37: // Enter or l - confirm and move focus to history
            isTagPanelFocused = false
            lastSelectedTagIndex = selectedTagIndex
            // Reset history selection to first item
            selectedIndex = 0
            return true

        case 45: // n - create new tag
            isCreatingTag = true
            editingTagName = ""
            return true

        case 15: // r - rename selected tag
            if selectedTagIndex < tagCount {
                let tag = tagService.tags[selectedTagIndex]
                editingTagName = tag.name
                isRenamingTag = true
            }
            return true

        case 2: // d - delete tag with confirmation
            if selectedTagIndex < tagCount {
                tagToDelete = tagService.tags[selectedTagIndex]
                isDeletingTagConfirm = true
            }
            return true

        default:
            break
        }

        return false
    }

    // MARK: - Tag Association Popup

    private func openTagAssociationPopup() {
        guard let item = selectedItem else { return }

        tagService.loadTags()

        // Load current item's tags
        itemTagIds = Set(tagService.getTagsForItem(itemId: item.id.uuidString).map { $0.id })

        tagAssociationPopupIndex = 0
        isCreatingTagInPopup = false
        newTagNameInPopup = ""
        isTagAssociationPopupOpen = true
    }

    private func closeTagAssociationPopup() {
        // Save the tag associations
        if let item = selectedItem {
            tagService.setTagsForItem(itemId: item.id.uuidString, tagIds: itemTagIds)
        }

        isTagAssociationPopupOpen = false
        isCreatingTagInPopup = false
        newTagNameInPopup = ""
    }

    private func handleTagAssociationPopupKey(keyCode: UInt16, event: NSEvent) -> Bool {
        let tagCount = tagService.tags.count

        // If creating tag, only handle ESC to cancel
        if isCreatingTagInPopup {
            if keyCode == 53 { // ESC
                cancelTagCreationInPopup()
                return true
            }
            // Let TextField handle other keys
            return false
        }

        switch keyCode {
        case 53: // ESC - close popup
            closeTagAssociationPopup()
            return true

        case 38, 125: // j or Down
            if tagCount > 0 {
                tagAssociationPopupIndex = (tagAssociationPopupIndex + 1) % tagCount
            }
            return true

        case 40, 126: // k or Up
            if tagCount > 0 {
                tagAssociationPopupIndex = (tagAssociationPopupIndex - 1 + tagCount) % tagCount
            }
            return true

        case 49, 36: // Space or Enter - toggle tag
            if tagAssociationPopupIndex < tagCount {
                let tag = tagService.tags[tagAssociationPopupIndex]
                if itemTagIds.contains(tag.id) {
                    itemTagIds.remove(tag.id)
                } else {
                    itemTagIds.insert(tag.id)
                }
            }
            return true

        case 45: // n - create new tag
            isCreatingTagInPopup = true
            newTagNameInPopup = ""
            return true

        default:
            break
        }

        return false
    }

    private func createTagInPopup() {
        guard !newTagNameInPopup.isEmpty else {
            cancelTagCreationInPopup()
            return
        }

        if let newTag = tagService.createTag(name: newTagNameInPopup) {
            // Auto-select the new tag for this item
            itemTagIds.insert(newTag.id)
            tagAssociationPopupIndex = tagService.tags.count - 1
        }

        isCreatingTagInPopup = false
        newTagNameInPopup = ""
    }

    private func cancelTagCreationInPopup() {
        isCreatingTagInPopup = false
        newTagNameInPopup = ""
    }

    // MARK: - Quick Preview

    private func previewItem(_ item: ClipboardItem) {
        guard let fullItem = clipboardMonitor.fullItem(for: item) else { return }

        switch fullItem.content {
        case .image:
            // Use separate window for images
            PreviewWindowController.shared.showPreview(for: fullItem)

        case .fileURL(let path):
            // Use Quick Look for files
            QuickLookController.shared.showPreview(for: path)

        default:
            // Use in-app preview for text/RTF
            previewingItem = fullItem
            isPreviewMode = true
        }
    }

    private func exitPreviewMode() {
        isPreviewMode = false
        previewingItem = nil
        previewOCRResult = nil
        isPerformingOCR = false
        previewScrollOffset = 0
    }

    private func performPreviewOCR(for item: ClipboardItem) {
        guard case .image(let data) = item.content else { return }

        isPerformingOCR = true
        previewOCRResult = nil

        Task {
            do {
                let text = try await OCRService.shared.recognizeText(from: data)
                await MainActor.run {
                    previewOCRResult = text
                    isPerformingOCR = false
                }
            } catch {
                await MainActor.run {
                    previewOCRResult = "\(L10n.t("popup.ocrFailed", "OCR failed")): \(error.localizedDescription)"
                    isPerformingOCR = false
                }
            }
        }
    }

    private func copyPreviewContent() {
        guard let previewingItem,
              let item = clipboardMonitor.fullItem(for: previewingItem) else { return }

        var textToCopy: String? = nil

        switch item.content {
        case .image:
            // Copy OCR result if available
            textToCopy = previewOCRResult
        case .text(let text):
            textToCopy = text
        case .richText(let data):
            if let attrString = NSAttributedString(rtf: data, documentAttributes: nil) {
                textToCopy = attrString.string
            }
        case .fileURL(let path):
            textToCopy = path
        }

        if let text = textToCopy, !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)

            // Show feedback
            showCopiedFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopiedFeedback = false
            }
        }
    }

    private func copyPlainText(from item: ClipboardItem) {
        guard let item = clipboardMonitor.fullItem(for: item) else { return }

        let textToCopy: String?
        switch item.content {
        case .image:
            textToCopy = nil
        case .text(let text):
            textToCopy = text
        case .richText(let data):
            textToCopy = NSAttributedString(rtf: data, documentAttributes: nil)?.string
        case .fileURL(let path):
            textToCopy = path
        }

        if let textToCopy, !textToCopy.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textToCopy, forType: .string)
        }
    }

    private func scrollPreview(by amount: CGFloat) {
        previewScrollOffset += amount
    }

    /// Scroll direction for half-page scroll
    private enum ScrollDirection {
        case up, down
    }

    /// Scroll history list by half page (approximately 5 items)
    private func scrollHistoryByHalfPage(direction: ScrollDirection) {
        let halfPage = 5  // Half page worth of items
        let itemCount = filteredItems.count
        guard itemCount > 0 else { return }

        isNavigatingViaKeyboard = true  // Enable scroll-to-center for keyboard navigation

        switch direction {
        case .down:
            selectedIndex = min(selectedIndex + halfPage, itemCount - 1)
        case .up:
            selectedIndex = max(selectedIndex - halfPage, 0)
        }
    }

    private func openInExternalApp(_ item: ClipboardItem) {
        guard let item = clipboardMonitor.fullItem(for: item) else { return }

        switch item.content {
        case .image(let data):
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vtool_preview.png")
            try? data.write(to: tempURL)
            NSWorkspace.shared.open(tempURL)

        case .fileURL(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))

        case .text(let text):
            if text.hasPrefix("/") || text.hasPrefix("~") {
                let expandedPath = (text as NSString).expandingTildeInPath
                if FileManager.default.fileExists(atPath: expandedPath) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: expandedPath))
                    return
                }
            }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vtool_preview.txt")
            try? text.write(to: tempURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempURL)

        case .richText(let data):
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vtool_preview.rtf")
            try? data.write(to: tempURL)
            NSWorkspace.shared.open(tempURL)
        }
    }

    private func previewOverlay(for item: ClipboardItem) -> some View {
        ZStack {
            // Dim background - click to close
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { exitPreviewMode() }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: item.content.icon)
                        .foregroundColor(theme.accent)
                    Text(L10n.t("popup.preview", "Preview"))
                        .font(.system(size: 14, weight: .semibold))

                    Spacer()

                    // Open in external app button
                    Button(action: {
                        openInExternalApp(item)
                        exitPreviewMode()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text(L10n.t("popup.open", "Open"))
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.tertiaryBackground)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Text(L10n.t("popup.shortcutsHint", "? for shortcuts"))
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryText)
                        .padding(.leading, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(theme.tertiaryBackground)

                // Alias and Tags Info
                if item.alias != nil || !tagService.getTagsForItem(itemId: item.originalId.uuidString).isEmpty {
                    VStack(spacing: 6) {
                        if let alias = item.alias, !alias.isEmpty {
                            HStack {
                                Text("\(L10n.t("popup.alias", "Alias")):")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(theme.secondaryText)
                                Text(alias)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.green)
                                Spacer()
                            }
                        }

                        TagsInfoRow(itemId: item.originalId.uuidString, tagService: tagService, theme: theme, fontSize: 13)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.secondaryBackground)
                }

                Divider()

                // Content - use different views based on content type
                switch item.content {
                case .text, .richText:
                    // Use ScrollableTextView for keyboard scroll support
                    let displayText: String = {
                        if case .text(let t) = item.content { return t }
                        if case .richText(let data) = item.content,
                           let attrStr = NSAttributedString(rtf: data, documentAttributes: nil) {
                            return attrStr.string
                        }
                        return ""
                    }()

                    let attrString: NSAttributedString = {
                        let base: NSAttributedString
                        if SyntaxHighlighter.shared.isLikelyCode(displayText),
                           let highlighted = SyntaxHighlighter.shared.highlight(displayText) {
                            base = highlighted
                        } else {
                            base = NSAttributedString(string: displayText, attributes: [
                                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                                .foregroundColor: NSColor.textColor
                            ])
                        }
                        return highlightedSearchText(base, maxMatches: 500)
                    }()

                    ScrollableTextView(
                        attributedText: attrString,
                        scrollOffset: $previewScrollOffset,
                        targetScroll: previewScrollOffset,  // Pass value to force update
                        lineHeight: 20,
                        pageHeight: 200
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                default:
                    // Use regular ScrollView for images and files
                    ScrollView {
                        previewContent(for: item)
                            .padding(16)
                    }
                }

                // OCR status bar for images
                if case .image = item.content {
                    Divider()
                    HStack {
                        if isPerformingOCR {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(L10n.t("popup.extractingText", "Extracting text..."))
                                .font(.system(size: 11))
                                .foregroundColor(theme.secondaryText)
                        } else if let ocrResult = previewOCRResult {
                            Image(systemName: "doc.text")
                                .foregroundColor(theme.accent)
                            Text("OCR: \(ocrResult.prefix(50))...")
                                .font(.system(size: 11))
                                .foregroundColor(theme.text)
                                .lineLimit(1)
                            Spacer()
                            Text(L10n.t("popup.copyWithCmdC", "⌘C to copy"))
                                .font(.system(size: 10))
                                .foregroundColor(theme.secondaryText)
                        } else {
                            Text(L10n.t("popup.ocrPrompt", "Press 'o' to extract text (OCR)"))
                                .font(.system(size: 11))
                                .foregroundColor(theme.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.tertiaryBackground)
                }
            }
            .frame(width: previewWidth(for: item), height: previewHeight(for: item))
            .background(theme.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 20)

            // Copied feedback overlay
            if showCopiedFeedback {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(L10n.t("popup.copied", "Copied!"))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.bottom, 50)
                }
                .transition(.opacity.combined(with: .scale))
                .animation(.easeOut(duration: 0.2), value: showCopiedFeedback)
            }
        }
    }

    private func previewWidth(for item: ClipboardItem) -> CGFloat {
        switch item.content {
        case .image:
            return 680  // Full width for images
        case .text(let text):
            return text.count > 500 ? 650 : 450
        case .fileURL:
            return 400
        case .richText:
            return 550
        }
    }

    private func previewHeight(for item: ClipboardItem) -> CGFloat {
        switch item.content {
        case .image:
            return 480  // Large height for images
        case .text(let text):
            let lines = text.components(separatedBy: .newlines).count
            return min(450, max(200, CGFloat(lines * 20 + 80)))
        case .fileURL:
            return 180
        case .richText:
            return 350
        }
    }

    @ViewBuilder
    private func previewContent(for item: ClipboardItem) -> some View {
        switch item.content {
        case .image(let data):
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(L10n.t("popup.unableLoadImage", "Unable to load image"))
                    .foregroundColor(theme.secondaryText)
            }

        case .text(let text):
            VStack(alignment: .leading, spacing: 8) {
                // Check if it's a file path
                if isFilePath(text) {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(theme.accent)
                        Text(L10n.t("popup.filePath", "File Path"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.secondaryText)
                    }
                    .padding(.bottom, 4)
                }

                // Simple text display (no syntax highlighting for performance)
                // Full syntax highlighting is only in preview mode (v key)
                        Text(highlightedSearchText(text))
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .fileURL(let path):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 32))
                        .foregroundColor(theme.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 16, weight: .semibold))
                        Text(path)
                            .font(.system(size: 11))
                            .foregroundColor(theme.secondaryText)
                            .lineLimit(2)
                    }
                }

                // File info
                if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                    Divider()
                    HStack(spacing: 24) {
                        if let size = attrs[.size] as? Int64 {
                            VStack {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(.system(size: 14, weight: .medium))
                                Text(L10n.t("popup.size", "Size"))
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.secondaryText)
                            }
                        }
                        if let modDate = attrs[.modificationDate] as? Date {
                            VStack {
                                Text(modDate, style: .date)
                                    .font(.system(size: 14, weight: .medium))
                                Text(L10n.t("popup.modified", "Modified"))
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.secondaryText)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .richText(let data):
            if let attrString = NSAttributedString(rtf: data, documentAttributes: nil) {
                // Helper to render content
                Group {
                    if SyntaxHighlighter.shared.isLikelyCode(attrString.string),
                       let highlighted = SyntaxHighlighter.shared.highlight(attrString.string) {
                        Text(AttributedString(highlightedSearchText(highlighted)))
                            .font(.custom("Menlo", size: 12))
                            .padding(8)
                            .background(Color(red: 0.15, green: 0.16, blue: 0.18))
                            .cornerRadius(4)
                    } else {
                        Text(AttributedString(highlightedSearchText(attrString)))
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(L10n.t("popup.unableLoadRichText", "Unable to load rich text"))
                    .foregroundColor(theme.secondaryText)
            }
        }
    }

    private func isFilePath(_ text: String) -> Bool {
        if text.hasPrefix("/") || text.hasPrefix("~") {
            let expandedPath = (text as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: expandedPath)
        }
        return false
    }


    private func handleCommandModeKey(keyCode: UInt16) -> Bool {
        switch keyCode {
        case 53: // Escape
            exitCommandMode()
            return true

        case 38, 125: // J or Down
            if commandMenuIndex < commandOptions.count - 1 {
                commandMenuIndex += 1
            }
            return true

        case 40, 126: // K or Up
            if commandMenuIndex > 0 {
                commandMenuIndex -= 1
            }
            return true

        case 36: // Enter
            let option = commandOptions[commandMenuIndex]
            exitCommandMode()
            option.action()
            return true

        default:
            return true
        }
    }

    private func enterCommandMode() {
        isCommandMode = true
        commandMenuIndex = 0
    }

    private func exitCommandMode() {
        isCommandMode = false
    }

    private func enterPositionMode(for item: ClipboardItem) {
        // For pinned items, find the original item in clipboard history
        let targetItem: ClipboardItem
        if item.isPinnedItem {
            // Find the original item using originalId
            if let original = clipboardMonitor.items.first(where: { $0.id == item.originalId }) {
                targetItem = original
            } else {
                targetItem = item  // Fallback to the pinned item itself
            }
        } else {
            targetItem = item
        }

        positionAnchorItem = targetItem
        isPositionMode = true

        // Find the index of the anchor in the new filtered list
        let items = getItemsAroundAnchor(targetItem)
        if let index = items.firstIndex(where: { $0.id == targetItem.id }) {
            selectedIndex = index
        }
    }

    private func exitPositionMode() {
        // Remember the currently selected item before exiting
        let currentItem = filteredItems[safe: selectedIndex]

        isPositionMode = false
        positionAnchorItem = nil

        // Find the same item's index in the full list
        if let item = currentItem,
           let newIndex = filteredItems.firstIndex(where: { $0.id == item.id }) {
            selectedIndex = newIndex
        }
        // If not found, selectedIndex stays as-is (will be clamped by filteredItems bounds if needed)
    }

    private func moveDown() {
        if filteredItems.isEmpty { return }
        isNavigatingViaKeyboard = true  // Enable scroll-to-center for keyboard navigation

        if selectedIndex < filteredItems.count - 1 {
            // Load more BEFORE moving if approaching the end AND there are more items
            if clipboardMonitor.hasMore && selectedIndex >= filteredItems.count - 11 {
                loadMoreItems()
            }
            selectedIndex += 1
        } else {
            // At the last item
            if clipboardMonitor.hasMore {
                // Try to load more
                let prevCount = filteredItems.count
                loadMoreItems()

                if filteredItems.count > prevCount {
                    // New items loaded, move to next
                    selectedIndex += 1
                    return
                }
            }
            // No more items or failed to load, wrap to first
            clipboardMonitor.loadFirstPage()
            selectedIndex = 0
        }
    }

    private func moveUp() {
        if filteredItems.isEmpty { return }
        isNavigatingViaKeyboard = true  // Enable scroll-to-center for keyboard navigation

        if selectedIndex > 0 {
            selectedIndex -= 1
        } else {
            // At first item of current page
            if clipboardMonitor.currentOffset > 0 {
                // Not at database beginning, load previous page FIRST
                let prevCount = filteredItems.count
                if clipboardMonitor.loadPreviousPage() {
                    let newItemsCount = filteredItems.count - prevCount
                    selectedIndex = max(0, newItemsCount - 1)
                }
            } else {
                // At database beginning, wrap to last page
                let lastIndex = clipboardMonitor.loadLastPage()
                selectedIndex = lastIndex
            }
        }
    }

    private func loadMoreItems() {
        clipboardMonitor.loadMore()
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Mode indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(modeColor)
                    .frame(width: 8, height: 8)
                Text(localizedModeName(displayMode))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.secondaryText)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(theme.tertiaryBackground)
            .cornerRadius(4)

            // Position mode indicator
            if isPositionMode, let anchor = positionAnchorItem {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                    Text(String(format: L10n.t("popup.around", "Around: %@..."), String(anchor.displayText.prefix(20))))
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.cyan.opacity(0.2))
                .foregroundColor(.cyan)
                .cornerRadius(4)
            }

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(theme.secondaryText)

                // Regex mode indicator
                if parseSearchQuery(searchText).isRegex {
                    Text("REGEX")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .cornerRadius(3)
                }

                TextField(L10n.t("popup.searchPlaceholder", "Type to filter... (f to search, /regex/ for regex)"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: themeManager.fontSize))
                    .focused($isSearchFocused)
                    .disabled(isPositionMode)
                    .onSubmit {
                        // First Enter in SEARCH mode = exit search (like ESC)
                        // Second Enter = paste
                        if searchModeEnterCount == 0 {
                            searchModeEnterCount = 1
                            isSearchFocused = false  // Exit SEARCH mode
                        } else if let item = selectedItem {
                            clipboardMonitor.paste(item: item)
                        }
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        isSearchFocused = false  // Back to NORMAL mode
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(theme.secondaryBackground)
            .cornerRadius(8)

            Spacer()

            // Type filter dropdown (disabled in position mode)
            if !isPositionMode {
                Picker("", selection: $selectedTypeFilter) {
                    ForEach(ContentTypeFilter.allCases, id: \.self) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            } else {
                Button(L10n.t("popup.exitPositionMode", "Exit Position Mode")) {
                    exitPositionMode()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Left List Panel

    private var leftListPanel: some View {
        VStack(spacing: 0) {
            if filteredItems.isEmpty {
                emptyStateView
            } else {
                historyListContainer
            }
        }
        .background(theme.background)
    }

    private var historyListContainer: some View {
        GeometryReader { listGeo in
            ScrollViewReader { proxy in
                historyListScrollView(proxy: proxy, listGeo: listGeo)
            }
        }
    }

    private func historyListScrollView(proxy: ScrollViewProxy, listGeo: GeometryProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                historyListItems(listGeo: listGeo)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .coordinateSpace(name: "HistoryScroll")
        .onAppear {
            clipboardMonitor.prefetchContent(around: selectedIndex, in: filteredItems)
        }
        .onPreferenceChange(ViewOffsetKey.self) { indices in
            self.visibleIndices = indices
        }
        .overlay(gotoOverlay)
        .onChange(of: selectedIndex) { newValue in
            clipboardMonitor.prefetchContent(around: newValue, in: filteredItems)

            // Only scroll to center when navigating via keyboard
            guard isNavigatingViaKeyboard else { return }
            if let item = filteredItems[safe: newValue] {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(item.displayId, anchor: .center)
                }
            }
            // Reset flag after scrolling
            isNavigatingViaKeyboard = false
        }
        .onChange(of: scrollToTopTrigger) { _ in
            // Scroll to top when window opens
            if let firstItem = filteredItems.first {
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(firstItem.displayId, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func historyListItems(listGeo: GeometryProxy) -> some View {
         ForEach(Array(filteredItems.enumerated()), id: \.element.displayId) { index, item in
             // Show separator between pinned items and normal items
             // Only show when PIN area is visible and has items
             if index == filteredPinnedItems.count && isPinAreaVisible && !filteredPinnedItems.isEmpty {
                 HStack {
                     VStack { Divider() }
                     Text(L10n.t("popup.history", "History"))
                         .font(.system(size: 9, weight: .medium))
                         .foregroundColor(theme.secondaryText)
                         .textCase(.uppercase)
                     VStack { Divider() }
                 }
                 .padding(.vertical, 4)
             }

             itemRow(for: item, index: index)
                 .background(
                     GeometryReader { itemGeo in
                         Color.clear.preference(
                             key: ViewOffsetKey.self,
                             value: calculateVisibility(
                                 itemFrame: itemGeo.frame(in: .named("HistoryScroll")),
                                 listHeight: listGeo.size.height,
                                 index: index
                             )
                         )
                     }
                 )
         }
    }

    private func calculateVisibility(itemFrame: CGRect, listHeight: CGFloat, index: Int) -> Set<Int> {
        let isVisible = itemFrame.maxY >= -10 && itemFrame.minY <= listHeight + 10
        return isVisible ? [index] : []
    }

    private var gotoOverlay: some View {
        Group {
            if isGotoMode {
                ZStack {
                    // Top-left 'g'
                    Text("g")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.teal.opacity(0.9))
                        )
                        .padding(.top, 10)
                        .padding(.leading, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    // Bottom-left 'G'
                    Text("G")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.teal.opacity(0.9))
                        )
                        .padding(.bottom, 10)
                        .padding(.leading, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .allowsHitTesting(false)
            }
        }
    }
    private func getShortcutChar(for index: Int) -> String? {
        guard isGotoMode || isSearchFocused else { return nil }

        // 只对visibleIndices中的项显示快捷键
        // visibleIndices由onAppear/onDisappear追踪
        guard visibleIndices.contains(index) else { return nil }

        // 按索引排序可见项，编号从第一个可见项开始
        let sortedVisible = visibleIndices.sorted()
        guard let offset = sortedVisible.firstIndex(of: index) else { return nil }

        // Search mode: only use numbers 1-9 to avoid conflict with CMD+A/C/V etc.
        let isLimited = isSearchFocused && !isGotoMode
        if isLimited && offset >= 9 { return nil }

        let shortcuts = "123456789abcdefhilmnopqrstvwxyzABCDEFHIJKLMNOPQRSTUVWXYZ"
        if offset >= 0 && offset < shortcuts.count {
            let idx = shortcuts.index(shortcuts.startIndex, offsetBy: offset)
            return String(shortcuts[idx])
        }
        return nil
    }

    @ViewBuilder
    private func itemRow(for item: ClipboardItem, index: Int) -> some View {
        // Show inline rename text field if this item is being renamed
        let isThisItemBeingRenamed = isRenamingItem && renamingItemId == item.displayId

        if isThisItemBeingRenamed {
            HStack(spacing: 12) {
                // Pencil icon with circle background
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 24, height: 24)
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                }

                // Text field with underline style
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("popup.rename", "Rename"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.blue)
                    TextField(L10n.t("popup.aliasPlaceholder", "Enter alias..."), text: $editingItemAlias)
                        .textFieldStyle(.plain)
                        .font(.system(size: themeManager.fontSize, weight: .medium))
                        .foregroundColor(theme.text)
                        .focused($isRenameInputFocused)
                        .onSubmit {
                            confirmRename()
                        }
                }

                Spacer()

                // Key hints as pill badges
                HStack(spacing: 6) {
                    Text("⏎ \(L10n.t("popup.save", "Save"))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(4)
                    Text("ESC")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(theme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.tertiaryBackground)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.secondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.5), lineWidth: 1.5)
                    )
            )
            .id("RENAME_\(item.displayId)")  // Different id to force view update
        } else {
            let searchHighlight = parseSearchQuery(searchText)
            CompactItemRow(
                item: item,
                index: index,
                isSelected: index == selectedIndex,
                isFocused: !isTagPanelFocused,
                isAnchor: isPositionMode && item.id == positionAnchorItem?.id,
                isPinned: item.isPinnedItem,
                isInSearchMode: isSearchFocused,
                fontSize: themeManager.fontSize,
                theme: theme,
                isGotoMode: isGotoMode,
                shortcutChar: getShortcutChar(for: index),
                searchQuery: searchHighlight.query,
                searchIsRegex: searchHighlight.isRegex
            )
            .id("ROW_\(item.displayId)")  // Stable ID to prevent view recreation and state loss
            .contentShape(Rectangle())
            .onTapGesture {
                let now = Date()
                let timeSinceLastClick = now.timeIntervalSince(lastClickTime)
                let isSameItem = lastClickedItemId == item.displayId

                // Double-click detection: same item within 300ms
                if isSameItem && timeSinceLastClick < 0.3 {
                    // Double-click: paste
                    clipboardMonitor.paste(item: item)
                    lastClickedItemId = nil
                    lastClickTime = .distantPast
                } else {
                    // Single-click: select (no scroll)
                    isNavigatingViaKeyboard = false
                    selectedIndex = index
                    isSearchFocused = false
                    lastClickedItemId = item.displayId
                    lastClickTime = now
                }
            }
            .contextMenu {
                Button {
                    clipboardMonitor.paste(item: item)
                } label: {
                    Label(L10n.t("popup.paste", "Paste"), systemImage: "doc.on.doc")
                }

                Button {
                    copyPlainText(from: item)
                } label: {
                    Label(L10n.t("popup.copyText", "Copy Text"), systemImage: "doc.on.clipboard")
                }

                Button {
                    clipboardMonitor.togglePin(item: item)
                } label: {
                    Label(
                        item.isPinnedItem ? L10n.t("popup.unpin", "Unpin") : L10n.t("popup.pin", "Pin"),
                        systemImage: "pin"
                    )
                }

                Button {
                    startRename(item: item)
                } label: {
                    Label(L10n.t("popup.rename", "Rename"), systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    clipboardMonitor.delete(item: item)
                } label: {
                    Label(L10n.t("popup.delete", "Delete"), systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Right Preview Panel

    private var rightPreviewPanel: some View {
        VStack(spacing: 0) {
            previewArea
            Divider()
            informationArea
        }
        .background(theme.secondaryBackground)
    }

    private var previewArea: some View {
        Group {
            if let item = selectedItem {
                if !item.isContentLoaded {
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(highlightedSearchText(item.displayText))
                            .font(.system(size: themeManager.fontSize))
                            .foregroundColor(theme.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
                    .onAppear {
                        clipboardMonitor.prefetchContent(around: selectedIndex, in: filteredItems, radius: 0)
                    }
                } else {
                    switch item.content {
                case .text(let string):
                    // Async loading for large text
                    if string.count > 5000 {
                        if isLoadingPreview && previewItemId == item.id {
                            VStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(L10n.t("popup.loadingPreview", "Loading preview..."))
                                    .font(.system(size: themeManager.fontSize))
                                    .foregroundColor(theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if previewItemId == item.id, let text = previewText {
                            // Loaded large text
                            let attrStr = highlightedSearchText(NSAttributedString(string: text, attributes: [
                                .font: NSFont.monospacedSystemFont(ofSize: themeManager.previewFontSize, weight: .regular),
                                .foregroundColor: NSColor.textColor
                            ]))
                            ScrollableTextView(
                                attributedText: attrStr,
                                scrollOffset: $previewScrollOffset,
                                targetScroll: previewScrollOffset,
                                lineHeight: 20,
                                pageHeight: 200
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // Trigger async load
                            Color.clear.onAppear {
                                loadPreviewAsync(for: item, text: string)
                            }
                        }
                    } else {
                        // Small text, render directly
                        let attrStr = highlightedSearchText(NSAttributedString(string: string, attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: themeManager.previewFontSize, weight: .regular),
                            .foregroundColor: NSColor.textColor
                        ]))
                        ScrollableTextView(
                            attributedText: attrStr,
                            scrollOffset: $previewScrollOffset,
                            targetScroll: previewScrollOffset,
                            lineHeight: 20,
                            pageHeight: 200
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                case .richText(let data):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if let attrString = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                                Text(AttributedString(highlightedSearchText(attrString)))
                                    .font(.system(size: themeManager.previewFontSize))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                    }

                case .image(let data):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .padding(16)
                    }

                case .fileURL(let path):
                    let url = URL(fileURLWithPath: path)
                    let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
                    let isImageFile = imageExtensions.contains(url.pathExtension.lowercased())

                    ScrollView {
                        VStack(alignment: .center, spacing: 0) {
                            // Image preview if it's an image file
                            if isImageFile, let nsImage = NSImage(contentsOfFile: path) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .cornerRadius(8)
                            } else {
                                // Default file icon for non-image files
                                VStack(spacing: 12) {
                                    Image(systemName: "doc.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(theme.accent)
                                    Text(url.lastPathComponent)
                                        .font(.system(size: themeManager.previewFontSize, weight: .medium))
                                        .foregroundColor(theme.text)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                    }
                    }
                }
            } else {
                VStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(theme.secondaryText.opacity(0.5))
                    Text(L10n.t("popup.selectPreview", "Select an item to preview"))
                        .font(.system(size: themeManager.fontSize))
                        .foregroundColor(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .onChange(of: selectedIndex) { _ in
            // Reset preview when selection changes
            previewItemId = nil
            previewText = nil
            isLoadingPreview = false
            previewScrollOffset = 0 // Reset scroll
            clipboardMonitor.prefetchContent(around: selectedIndex, in: filteredItems)
        }
    }

    /// Load large text preview asynchronously to prevent UI blocking
    private func loadPreviewAsync(for item: ClipboardItem, text: String) {
        let itemId = item.id

        // Use Task to avoid blocking the main thread
        Task {
            // Small delay to let navigation animation complete first
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms

            await MainActor.run {
                previewItemId = itemId
                isLoadingPreview = true
            }

            // Process text in background
            let maxChars = 10000
            let displayText = text.count > maxChars
                ? String(text.prefix(maxChars)) + "\n\n" + String(format: L10n.t("popup.moreCharacters", "... (%d more characters)"), text.count - maxChars)
                : text

            // Another small delay to let the loading indicator render
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

            await MainActor.run {
                // Only update if still showing the same item
                if self.previewItemId == itemId {
                    self.previewText = displayText
                    self.isLoadingPreview = false
                }
            }
        }
    }

    private var informationArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("popup.information", "Information"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.secondaryText)

                Spacer()

                // Quick actions
                if selectedItem != nil {
                    Button(action: { enterCommandMode() }) {
                        HStack(spacing: 2) {
                            Text(":")
                                .font(.system(size: 10, design: .monospaced))
                            Text(L10n.t("popup.actions", "Actions"))
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.tertiaryBackground)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let item = selectedItem {
                VStack(spacing: 4) {
                    // Show alias if present
                    if let alias = item.alias, !alias.isEmpty {
                        HStack {
                            Text(L10n.t("popup.alias", "Alias"))
                                .font(.system(size: themeManager.fontSize - 1))
                                .foregroundColor(theme.secondaryText)
                            Spacer()
                            Text(alias)
                                .font(.system(size: themeManager.fontSize - 1, weight: .medium))
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }
                    }

                    InfoRow(label: L10n.t("popup.application", "Application"), value: item.sourceApp ?? L10n.t("popup.unknown", "Unknown"), theme: theme, fontSize: themeManager.fontSize)
                    InfoRow(label: L10n.t("popup.contentType", "Content type"), value: item.content.typeName, theme: theme, fontSize: themeManager.fontSize)
                    InfoRow(label: L10n.t("popup.copiedAt", "Copied at"), value: formatDate(item.createdAt), theme: theme, fontSize: themeManager.fontSize)
                    InfoRow(label: L10n.t("popup.position", "Position"), value: "#\(item.position)", theme: theme, fontSize: themeManager.fontSize)

                    // Image-specific info
                    if case .image(let data) = item.content {
                        if let nsImage = NSImage(data: data) {
                            InfoRow(label: L10n.t("popup.resolution", "Resolution"), value: "\(Int(nsImage.size.width))×\(Int(nsImage.size.height))", theme: theme, fontSize: themeManager.fontSize)
                        }
                        InfoRow(label: L10n.t("popup.size", "Size"), value: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file), theme: theme, fontSize: themeManager.fontSize)
                    }

                    // Text character count
                    if case .text(let string) = item.content {
                        InfoRow(label: L10n.t("popup.characters", "Characters"), value: "\(string.count)", theme: theme, fontSize: themeManager.fontSize)
                    }

                    // File-specific info
                    if case .fileURL(let path) = item.content {
                        let url = URL(fileURLWithPath: path)

                        // File name
                        HStack {
                            Text(L10n.t("popup.fileName", "File name"))
                                .font(.system(size: themeManager.fontSize - 1))
                                .foregroundColor(theme.secondaryText)
                            Spacer()
                            Text(url.lastPathComponent)
                                .font(.system(size: themeManager.fontSize - 1))
                                .foregroundColor(theme.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        // File path (clickable to copy)
                        HStack {
                            Text(L10n.t("popup.path", "Path"))
                                .font(.system(size: themeManager.fontSize - 1))
                                .foregroundColor(theme.secondaryText)
                            Spacer()
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                            }) {
                                HStack(spacing: 4) {
                                    Text(path)
                                        .font(.system(size: themeManager.fontSize - 1))
                                        .foregroundColor(theme.accent)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10))
                                        .foregroundColor(theme.accent)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(path)  // Show full path on hover
                        }

                        let fileInfo = getFileInfo(path: path)
                        if let size = fileInfo.size {
                            InfoRow(label: L10n.t("popup.fileSize", "File size"), value: size, theme: theme, fontSize: themeManager.fontSize)
                        }
                        if let modified = fileInfo.modified {
                            InfoRow(label: L10n.t("popup.modified", "Modified"), value: modified, theme: theme, fontSize: themeManager.fontSize)
                        }
                    }

                    // PIN status display
                    if item.isDirectPinned || item.isPinnedItem {
                        HStack {
                            Text(L10n.t("popup.pinStatus", "PIN Status"))
                                .font(.system(size: themeManager.fontSize - 1))
                                .foregroundColor(theme.secondaryText)
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 10))
                                let (statusText, statusColor): (String, Color) = {
                                    switch item.pinType {
                                    case .direct: return (L10n.t("popup.pinDirect", "Direct"), .orange)
                                    case .tag: return (L10n.t("popup.pinTag", "Tag"), .blue)
                                    case .both: return (L10n.t("popup.pinBoth", "Direct + Tag"), .purple)
                                    case .none: return (item.isDirectPinned ? L10n.t("popup.pinDirect", "Direct") : L10n.t("popup.pinned", "Pinned"), .orange)
                                    }
                                }()
                                Text(statusText)
                                    .font(.system(size: themeManager.fontSize - 1, weight: .medium))
                                    .foregroundColor(statusColor)
                            }
                        }
                    }

                    // Tags display
                    TagsInfoRow(itemId: item.id.uuidString, tagService: tagService, theme: theme, fontSize: themeManager.fontSize)
                }
            } else {
                Text(L10n.t("popup.noItemSelected", "No item selected"))
                    .font(.system(size: themeManager.fontSize))
                    .foregroundColor(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(minHeight: 180)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clipboard")
                .font(.system(size: 48))
                .foregroundColor(theme.secondaryText)

            Text(showFavoritesOnly ? L10n.t("popup.noFavorites", "No favorites yet") : L10n.t("popup.empty", "Clipboard is empty"))
                .font(.system(size: themeManager.fontSize + 2, weight: .medium))
                .foregroundColor(theme.secondaryText)

            Text(L10n.t("popup.emptySubtitle", "Copied items will appear here"))
                .font(.system(size: themeManager.fontSize))
                .foregroundColor(theme.secondaryText.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 8) {
            // Left: Pagination info
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundColor(theme.accent)
                Text("\(selectedIndex + 1) / \(clipboardMonitor.itemCount)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.secondaryText)
            }

            // Center: Tag filter bar (inline, scrollable)
            if isPinAreaVisible && !tagService.tags.isEmpty && !isSearchFocused {
                inlineTagFilterBar
            } else {
                Spacer()
            }

            // Right: VIM hints
            HStack(spacing: 8) {
                if isPreviewMode {
                    KeyHint(key: "ESC", action: L10n.t("hint.exit", "exit"), theme: theme)
                    KeyHint(key: "j/k", action: L10n.t("hint.scroll", "scroll"), theme: theme)
                    KeyHint(key: "CMD+C", action: L10n.t("hint.copy", "copy"), theme: theme)
                } else if isTypeFilterMode {
                    KeyHint(key: "ESC", action: L10n.t("hint.cancel", "cancel"), theme: theme)
                    KeyHint(key: "↑/↓", action: L10n.t("hint.select", "select"), theme: theme)
                    KeyHint(key: "⏎", action: L10n.t("hint.confirm", "confirm"), theme: theme)
                } else if isTagAssociationPopupOpen {
                    KeyHint(key: "ESC", action: L10n.t("hint.cancel", "cancel"), theme: theme)
                    KeyHint(key: "⏎", action: L10n.t("hint.save", "save"), theme: theme)
                } else if isCommandMode {
                    KeyHint(key: "ESC", action: L10n.t("hint.cancel", "cancel"), theme: theme)
                    KeyHint(key: "TAB", action: L10n.t("hint.nav", "nav"), theme: theme)
                    KeyHint(key: "⏎", action: L10n.t("hint.exec", "exec"), theme: theme)
                } else if isPositionMode {
                    KeyHint(key: "ESC", action: L10n.t("hint.exit", "exit"), theme: theme)
                } else if isTagPanelFocused {
                    KeyHint(key: "ESC", action: L10n.t("hint.back", "back"), theme: theme)
                    KeyHint(key: "←/→", action: L10n.t("hint.nav", "nav"), theme: theme)
                    KeyHint(key: "⏎", action: L10n.t("hint.toggle", "toggle"), theme: theme)
                } else if isRenamingItem {
                    KeyHint(key: "ESC", action: L10n.t("hint.cancel", "cancel"), theme: theme)
                    KeyHint(key: "⏎", action: L10n.t("hint.save", "save"), theme: theme)
                } else if isGotoMode {
                    KeyHint(key: "ESC", action: L10n.t("hint.cancel", "cancel"), theme: theme)
                    KeyHint(key: "a-z", action: L10n.t("hint.select", "select"), theme: theme)
                } else if isSearchFocused {
                    // Search Mode Hints
                    KeyHint(key: "CMD+1-9", action: L10n.t("hint.select", "select"), theme: theme)
                    KeyHint(key: "⌃d/u", action: L10n.t("hint.scroll", "scroll"), theme: theme)
                    KeyHint(key: "ESC", action: L10n.t("hint.exit", "exit"), theme: theme)
                } else {
                    // Normal Mode Hints
                    KeyHint(key: "j/k", action: L10n.t("hint.nav", "nav"), theme: theme)
                    KeyHint(key: "⏎", action: L10n.t("hint.paste", "paste"), theme: theme)
                    KeyHint(key: "p", action: L10n.t("hint.locate", "locate"), theme: theme)
                    KeyHint(key: ":", action: L10n.t("hint.menu", "menu"), theme: theme)
                    KeyHint(key: "f", action: L10n.t("hint.search", "search"), theme: theme)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Inline Tag Filter Bar (compact, for footer)

    @State private var tagScrollPosition: Int = 0  // Current scroll position (tag index)

    private var inlineTagFilterBar: some View {
        HStack(spacing: 4) {
            // Left arrow button (only show if can scroll left)
            if tagScrollPosition > 0 {
                Button(action: {
                    tagScrollPosition = max(0, tagScrollPosition - 3)
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.secondaryText)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }

            // Tags container
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(tagService.tags.enumerated()), id: \.element.id) { index, tag in
                            let shortcutKey = shortcutKeyForIndex(index)
                            let isSelected = selectedPinnedTagIds.contains(tag.id)

                            Button(action: {
                                togglePinnedTagSelection(tag.id)
                            }) {
                                HStack(spacing: 2) {
                                    Text(shortcutKey)
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(isSelected ? theme.accent : theme.secondaryText)
                                    Text(tag.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(isSelected ? theme.accent : theme.text.opacity(0.7))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(isSelected ? theme.accent.opacity(0.2) : theme.secondaryBackground.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 1)
                                )
                                .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onChange(of: tagScrollPosition) { newPosition in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newPosition, anchor: .leading)
                    }
                }
                .onChange(of: tagBarScrollOffset) { _ in
                    tagScrollPosition = Int(tagBarScrollOffset)
                }
            }

            // Right arrow button (only show if can scroll right)
            if tagScrollPosition < tagService.tags.count - 1 && tagService.tags.count > 5 {
                Button(action: {
                    tagScrollPosition = min(tagService.tags.count - 1, tagScrollPosition + 3)
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.secondaryText)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // NOTE: tagFilterBar was removed - inlineTagFilterBar is used instead

    /// Get shortcut key string for index (CMD+1-9, CMD+a-z)
    private func shortcutKeyForIndex(_ index: Int) -> String {
        if index < 9 {
            return "⌘\(index + 1)"  // ⌘1, ⌘2, etc.
        } else if index < 35 {
            let letterIndex = index - 9
            let letter = Character(UnicodeScalar(Int(("a" as Character).asciiValue!) + letterIndex)!)
            return "⌘" + String(letter)  // ⌘a, ⌘b, etc.
        } else {
            return ""
        }
    }

    /// Toggle selection of a pinned tag
    private func togglePinnedTagSelection(_ tagId: String) {
        if selectedPinnedTagIds.contains(tagId) {
            selectedPinnedTagIds.remove(tagId)
        } else {
            selectedPinnedTagIds.insert(tagId)
        }
    }

    /// Toggle all tags selection (Ctrl+0)
    private func toggleAllPinnedTags() {
        let allTagIds = Set(tagService.tags.map { $0.id })
        if selectedPinnedTagIds == allTagIds {
            // All selected, deselect all
            selectedPinnedTagIds.removeAll()
        } else {
            // Not all selected, select all
            selectedPinnedTagIds = allTagIds
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func getFileInfo(path: String) -> (size: String?, modified: String?) {
        guard FileManager.default.fileExists(atPath: path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            return (nil, nil)
        }

        var size: String? = nil
        var modified: String? = nil

        if let fileSize = attrs[.size] as? Int64 {
            size = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        }

        if let modDate = attrs[.modificationDate] as? Date {
            modified = formatDate(modDate)
        }

        return (size, modified)
    }
}

// MARK: - Key Hint View
struct KeyHint: View {
    let key: String
    let action: String
    let theme: ThemeColors

    var body: some View {
        HStack(spacing: 2) {
            Text(key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary)
            Text(action)
                .font(.system(size: 10))
                .foregroundColor(theme.secondaryText)
        }
    }
}

// MARK: - Search Match Highlighting
enum SearchMatchHighlighter {
    private static let highlightAttributes: [NSAttributedString.Key: Any] = [
        .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.55),
        .underlineStyle: NSUnderlineStyle.single.rawValue
    ]

    static func attributedString(
        _ text: String,
        query: String?,
        isRegex: Bool,
        maxMatches: Int = 200
    ) -> AttributedString {
        let base = NSAttributedString(string: text)
        return AttributedString(apply(
            to: base,
            query: query,
            isRegex: isRegex,
            maxMatches: maxMatches
        ))
    }

    static func apply(
        to attributedString: NSAttributedString,
        query: String?,
        isRegex: Bool,
        maxMatches: Int = 200
    ) -> NSAttributedString {
        guard maxMatches > 0,
              let query = query?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty,
              !attributedString.string.isEmpty else {
            return attributedString
        }

        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutable.length)

        if isRegex {
            guard let regex = try? NSRegularExpression(pattern: query, options: [.caseInsensitive]) else {
                return attributedString
            }

            var applied = 0
            regex.enumerateMatches(in: mutable.string, options: [], range: fullRange) { match, _, stop in
                guard let range = match?.range, range.length > 0 else { return }
                mutable.addAttributes(highlightAttributes, range: range)
                applied += 1
                if applied >= maxMatches {
                    stop.pointee = true
                }
            }
            return mutable
        }

        let nsString = mutable.string as NSString
        var searchRange = fullRange
        var applied = 0

        while searchRange.length > 0 && applied < maxMatches {
            let found = nsString.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )

            if found.location == NSNotFound || found.length == 0 {
                break
            }

            mutable.addAttributes(highlightAttributes, range: found)
            applied += 1

            let nextLocation = found.location + found.length
            if nextLocation >= nsString.length {
                break
            }
            searchRange = NSRange(location: nextLocation, length: nsString.length - nextLocation)
        }

        return mutable
    }

    static func containsMatch(in text: String, query: String, isRegex: Bool) -> Bool {
        guard !query.isEmpty, !text.isEmpty else { return false }

        if isRegex {
            guard let regex = try? NSRegularExpression(pattern: query, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(location: 0, length: (text as NSString).length)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }

        return text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

// MARK: - Key Event Handling View
struct KeyEventHandlingView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyEventView {
        let view = KeyEventView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyEventView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

class KeyEventView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let onKeyDown = self?.onKeyDown, onKeyDown(event) {
                return nil
            }
            return event
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        if newWindow == nil, let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    override func keyDown(with event: NSEvent) {
        if let onKeyDown = onKeyDown, onKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Compact Item Row
struct CompactItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let isFocused: Bool  // Whether history list has focus (not tag panel)
    let isAnchor: Bool
    var isPinned: Bool = false  // Whether this is a pinned item
    var isInSearchMode: Bool = false  // Whether SEARCH mode is active (semi-transparent selection)
    let fontSize: Double
    let theme: ThemeColors
    var isGotoMode: Bool = false
    var shortcutChar: String? = nil
    var searchQuery: String? = nil
    var searchIsRegex: Bool = false
    @State private var isHovered = false

    private var backgroundColor: Color {
        if isAnchor {
            return Color.cyan.opacity(0.25)
        } else if isSelected {
            // Show dimmed selection when not focused (tag panel has focus)
            // Also show dimmed when in SEARCH mode (first Enter = exit, not paste)
            if isInSearchMode {
                return theme.selection.opacity(0.15)  // Extra dim in SEARCH mode
            }
            return isFocused ? theme.selection : theme.selection.opacity(0.4)
        } else if isHovered {
            return theme.hover
        }
        return Color.clear
    }

    var body: some View {
        HStack(spacing: 10) {
            // Anchor/Pin/Index indicator
            if let char = shortcutChar, !char.isEmpty {
                // GOTO Mode or Search Mode: Show shortcut badge (Priority over Pin/Anchor)
                Text(char)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(theme.accent.opacity(0.8))
                    .cornerRadius(4)
            } else if isAnchor {
                ZStack {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 18, height: 18)
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                }
            } else if isPinned {
                // Pinned item indicator with color based on pin type
                // Orange = direct, Blue = tag, Purple = both
                let pinColor: Color = {
                    switch item.pinType {
                    case .direct: return .orange
                    case .tag: return .blue
                    case .both: return .purple
                    case .none: return .orange  // Fallback
                    }
                }()
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(pinColor)
                    .frame(width: 18)
            } else {
                // Normal Mode: No index displayed (per user request)
                Spacer()
                    .frame(width: 18)
            }

            // Icon
            itemIcon
                .frame(width: 24, height: 24)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(SearchMatchHighlighter.attributedString(
                    item.displayText,
                    query: searchQuery,
                    isRegex: searchIsRegex
                ))
                    .font(.system(size: fontSize, weight: isAnchor ? .semibold : .regular))
                    .foregroundColor(isAnchor ? .cyan : theme.text)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let app = item.sourceApp {
                        Text(app)
                            .font(.system(size: fontSize - 2))
                            .foregroundColor(theme.secondaryText)
                    }
                    Text(item.formattedTime)
                        .font(.system(size: fontSize - 2))
                        .foregroundColor(theme.secondaryText.opacity(0.7))
                }
            }

            Spacer()

            // Anchor label
            if isAnchor {
                Text(L10n.t("popup.anchor", "ANCHOR"))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan)
                    .cornerRadius(4)
            }

            // PIN label badge - shows on HISTORY items that are pinned (not on PIN section items)
            // Check isDirectPinned but exclude items that are in PIN section (have virtualId)
            if item.isDirectPinned && item.virtualId == nil {
                Text(L10n.t("popup.pinnedBadge", "PINNED"))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .cornerRadius(3)
            }

            // Alias badge (shows when item has custom alias)
            if let alias = item.alias, !alias.isEmpty {
                Text(alias)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(3)
            }

            // Favorite indicator
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isAnchor ? Color.cyan : (isSelected ? theme.accent.opacity(0.5) : Color.clear), lineWidth: isAnchor ? 2 : 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var itemIcon: some View {
        switch item.content {
        case .text:
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
        case .richText:
            Image(systemName: "doc.richtext")
                .foregroundColor(.purple)
        case .image(let data):
            if item.isContentLoaded,
               !data.isEmpty,
               let thumbnail = ThumbnailService.shared.thumbnail(for: data, id: item.id.uuidString) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.green)
            }
        case .fileURL:
            Image(systemName: "doc.fill")
                .foregroundColor(.orange)
        }
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    let theme: ThemeColors
    let fontSize: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: fontSize - 1))
                .foregroundColor(theme.secondaryText)

            Spacer()

            Text(value)
                .font(.system(size: fontSize - 1))
                .foregroundColor(theme.text)
        }
    }
}

// MARK: - ClipboardContent Extension
extension ClipboardContent {
    var typeName: String {
        switch self {
        case .text:
            return L10n.t("contentType.plainText", "Plain Text")
        case .richText:
            return L10n.t("contentType.richText", "Rich Text (Formatted)")
        case .image:
            return L10n.t("contentType.image", "Image")
        case .fileURL:
            return L10n.t("contentType.fileReference", "File Reference")
        }
    }
}

// MARK: - Safe Array Access
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Tags Info Row
struct TagsInfoRow: View {
    let itemId: String
    @ObservedObject var tagService: TagService
    let theme: ThemeColors
    let fontSize: CGFloat

    private var itemTags: [Tag] {
        tagService.getTagsForItem(itemId: itemId)
    }

    var body: some View {
        if !itemTags.isEmpty {
            HStack(alignment: .top, spacing: 4) {
                Text(L10n.t("popup.tags", "Tags"))
                    .font(.system(size: fontSize - 2))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 80, alignment: .leading)

                // Wrapped flow of tag badges
                FlowLayout(spacing: 4) {
                    ForEach(itemTags, id: \.id) { tag in
                        Text(tag.name)
                            .font(.system(size: fontSize - 3))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.accent.opacity(0.2))
                            .foregroundColor(theme.accent)
                            .cornerRadius(4)
                    }
                }

                Spacer()
            }
        }
    }
}

// Simple Flow Layout for tag badges
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(from: proposal, subviews)
        return CGSize(width: proposal.width ?? .infinity, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(from: proposal, subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(from proposal: ProposedViewSize, _ subviews: Subviews) -> (height: CGFloat, offsets: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (y + rowHeight, offsets)
    }
}

#Preview {
    PopupWindowView()
}

// MARK: - Flipped Clip View for proper top-to-bottom scrolling
class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

// MARK: - Scrollable Text View with Keyboard Navigation
struct ScrollableTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    @Binding var scrollOffset: CGFloat
    var targetScroll: CGFloat  // Plain property to force update
    let lineHeight: CGFloat
    let pageHeight: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false  // Keep scroller visible
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 0.1, green: 0.11, blue: 0.13, alpha: 1.0)

        // Use flipped clip view for proper top-aligned scrolling
        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        // Create text view with proper setup
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Set initial content
        textView.textStorage?.setAttributedString(attributedText)

        scrollView.documentView = textView

        return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: ()) {
        // Cleanup if needed
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // ... (rest of implementation)
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update container width to match scroll view
        textView.textContainer?.size = NSSize(
            width: scrollView.contentSize.width - 24,  // Account for insets
            height: CGFloat.greatestFiniteMagnitude
        )

        // Update text content or attributes if changed
        if textView.textStorage?.isEqual(to: attributedText) != true {
            textView.textStorage?.setAttributedString(attributedText)
        }

        // Layout to get correct size
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        // Size text view to fit content
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            let usedRect = layoutManager.usedRect(for: container)
            textView.frame = NSRect(
                x: 0,
                y: 0,
                width: scrollView.contentSize.width,
                height: max(usedRect.height + 24, scrollView.contentSize.height)  // At least scroll view height
            )
        }

        // Apply scroll offset with animation to ensure update
        let contentHeight = textView.frame.height
        let visibleHeight = scrollView.contentSize.height
        let maxScroll = max(0, contentHeight - visibleHeight)
        let clampedOffset = min(max(0, targetScroll), maxScroll)  // Use targetScroll

        // Ensure binding is updated if clamped
        if scrollOffset != clampedOffset {
            DispatchQueue.main.async {
                scrollOffset = clampedOffset
            }
        }

        let clipView = scrollView.contentView
        let newOrigin = NSPoint(x: 0, y: clampedOffset)

        // Always apply scroll position
        if clipView.bounds.origin.y != clampedOffset {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                context.allowsImplicitAnimation = true
                clipView.animator().setBoundsOrigin(newOrigin)
            }
            scrollView.reflectScrolledClipView(clipView)
        }
    }
}

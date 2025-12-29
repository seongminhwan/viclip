import SwiftUI
import AppKit
import Combine

struct PopupWindowView: View {
    @ObservedObject private var clipboardMonitor = ClipboardMonitor.shared
    @ObservedObject private var themeManager = ThemeManager.shared
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
    
    @Environment(\.colorScheme) private var colorScheme
    
    enum ContentTypeFilter: String, CaseIterable {
        case all = "All Types"
        case text = "Text"
        case image = "Image"
        case file = "File"
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
            CommandOption(icon: "doc.on.doc", title: "Paste", shortcut: "⏎") {
                clipboardMonitor.paste(item: item)
            },
            CommandOption(icon: "location", title: "Locate in Timeline", shortcut: "p") {
                enterPositionMode(for: item)
            },
            CommandOption(icon: item.isFavorite ? "star.fill" : "star", title: item.isFavorite ? "Remove from Favorites" : "Add to Favorites", shortcut: "f") {
                clipboardMonitor.toggleFavorite(item: item)
            },
            CommandOption(icon: "plus.square.on.square", title: "Add to Paste Queue", shortcut: "q") {
                sequentialPaster.addToQueue(item)
            },
            CommandOption(icon: "trash", title: "Delete", shortcut: "d") {
                clipboardMonitor.delete(item: item)
            }
        ]
    }
    
    private var filteredPinnedItems: [ClipboardItem] {
        var filteredPinned = pinnedItems
        
        // Apply search filter to pinned items
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filteredPinned = filteredPinned.filter { item in
                item.content.preview.lowercased().contains(query)
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
        var items = clipboardMonitor.items
        
        // Filter favorites only
        if showFavoritesOnly {
            items = items.filter { $0.isFavorite }
        }
        
        // Filter by type
        switch selectedTypeFilter {
        case .all:
            break
        case .text:
            items = items.filter {
                if case .text = $0.content { return true }
                if case .richText = $0.content { return true }
                return false
            }
        case .image:
            items = items.filter {
                if case .image = $0.content { return true }
                return false
            }
        case .file:
            items = items.filter {
                if case .fileURL = $0.content { return true }
                return false
            }
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
        filteredItems[safe: selectedIndex]
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
        !isSearchFocused && !isCommandMode
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
            vimEngine.resetState()
            // Start in NORMAL mode (search not focused)
            isSearchFocused = false
            // Reload items to get fresh data
            clipboardMonitor.setSearchQuery(nil, tagIds: nil)
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
                        // Use unified interface to set search query with current tag filter
                        let tagIds = Array(tagService.selectedTagIds)
                        clipboardMonitor.setSearchQuery(newValue.isEmpty ? nil : newValue, tagIds: tagIds.isEmpty ? nil : tagIds)
                        selectedIndex = 0  // Reset selection on new search
                    }
                }
            }
        }
        .onChange(of: tagService.selectedTagIds) { newValue in
            // Real-time tag filtering: reload items when tag selection changes
            let tagIds = Array(newValue)
            clipboardMonitor.setSearchQuery(searchText.isEmpty ? nil : searchText, tagIds: tagIds.isEmpty ? nil : tagIds)
            selectedIndex = 0  // Reset selection
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
                    Text("Actions")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("ESC to close")
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
                    Text("Filtered")
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
                HStack {
                    Image(systemName: "keyboard")
                        .foregroundColor(theme.accent)
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 14, weight: .semibold))
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
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(currentContextShortcuts.enumerated()), id: \.element.key) { index, shortcut in
                                HStack {
                                    Text(shortcut.key)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(index == helpScrollIndex ? .white : theme.accent)
                                        .frame(width: 80, alignment: .leading)
                                    Text(shortcut.description)
                                        .font(.system(size: 12))
                                        .foregroundColor(index == helpScrollIndex ? .white : theme.text)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(index == helpScrollIndex ? theme.accent : Color.clear)
                                .cornerRadius(4)
                                .id(index)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 300)
                    .onChange(of: helpScrollIndex) { newIndex in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
                
                Divider()
                
                // Footer
                HStack {
                    Text("Press")
                    Text("?")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.tertiaryBackground)
                        .cornerRadius(3)
                    Text("or")
                    Text("ESC")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.tertiaryBackground)
                        .cornerRadius(3)
                    Text("to close")
                }
                .font(.system(size: 10))
                .foregroundColor(theme.secondaryText)
                .padding(12)
            }
            .frame(width: 350)
            .background(theme.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }
    
    private var currentContextName: String {
        if isPreviewMode, let item = previewingItem {
            switch item.content {
            case .image: return "IMAGE PREVIEW"
            case .text: return "TEXT PREVIEW"
            case .richText: return "TEXT PREVIEW"
            case .fileURL: return "FILE PREVIEW"
            }
        } else if isTagPanelOpen && isTagPanelFocused {
            return "TAG PANEL"
        } else if isTagPanelOpen && !isTagPanelFocused {
            return "TAG HISTORY"
        } else if isCommandMode {
            return "COMMAND"
        } else if isSearchFocused {
            return "SEARCH"
        } else if !searchText.isEmpty {
            return "FILTERED"
        } else {
            return "NORMAL"
        }
    }
    
    private struct ShortcutInfo: Identifiable {
        let key: String
        let description: String
        var id: String { key }
    }
    
    private var currentContextShortcuts: [ShortcutInfo] {
        let kb = keyBindingManager
        
        // Preview mode shortcuts
        if isPreviewMode, let item = previewingItem {
            switch item.content {
            case .image:
                return [
                    ShortcutInfo(key: kb.binding(for: .previewOCR).displayString, description: "Extract text (OCR)"),
                    ShortcutInfo(key: kb.binding(for: .previewCopy).displayString, description: "Copy OCR result"),
                    ShortcutInfo(key: kb.binding(for: .previewOpenExternal).displayString, description: "Open in external app"),
                    ShortcutInfo(key: kb.binding(for: .escape).displayString + " / v", description: "Close preview"),
                    ShortcutInfo(key: "?", description: "Show this help"),
                ]
            case .text, .richText:
                return [
                    ShortcutInfo(key: kb.binding(for: .previewScrollDown).displayString, description: "Scroll down"),
                    ShortcutInfo(key: kb.binding(for: .previewScrollUp).displayString, description: "Scroll up"),
                    ShortcutInfo(key: kb.binding(for: .previewHalfPageDown).displayString, description: "Half page down"),
                    ShortcutInfo(key: kb.binding(for: .previewHalfPageUp).displayString, description: "Half page up"),
                    ShortcutInfo(key: kb.binding(for: .previewCopy).displayString, description: "Copy content"),
                    ShortcutInfo(key: kb.binding(for: .previewOpenExternal).displayString, description: "Open in external app"),
                    ShortcutInfo(key: kb.binding(for: .escape).displayString + " / v", description: "Close preview"),
                    ShortcutInfo(key: "?", description: "Show this help"),
                ]
            case .fileURL:
                return [
                    ShortcutInfo(key: kb.binding(for: .previewOpenExternal).displayString, description: "Open in Finder"),
                    ShortcutInfo(key: kb.binding(for: .escape).displayString + " / v", description: "Close preview"),
                    ShortcutInfo(key: "?", description: "Show this help"),
                ]
            }
        } else if isTagPanelOpen && isTagPanelFocused {
            return [
                ShortcutInfo(key: "j / ↓", description: "Move down"),
                ShortcutInfo(key: "k / ↑", description: "Move up"),
                ShortcutInfo(key: "Space", description: "Toggle tag selection"),
                ShortcutInfo(key: "n", description: "Create new tag"),
                ShortcutInfo(key: "r", description: "Rename tag"),
                ShortcutInfo(key: "d", description: "Delete tag"),
                ShortcutInfo(key: "⇧P", description: "Toggle tag pin"),
                ShortcutInfo(key: "l / ⏎", description: "Focus history list"),
                ShortcutInfo(key: "⎋", description: "Close tag panel"),
            ]
        } else if isTagPanelOpen && !isTagPanelFocused {
            return [
                ShortcutInfo(key: "j / ↓", description: "Move down"),
                ShortcutInfo(key: "k / ↑", description: "Move up"),
                ShortcutInfo(key: "⏎", description: "Paste selected item"),
                ShortcutInfo(key: "t", description: "Tag current item"),
                ShortcutInfo(key: "h / ⎋", description: "Return to tag list"),
            ]
        } else if isSearchFocused {
            return [
                ShortcutInfo(key: "j / ↓", description: "Move down"),
                ShortcutInfo(key: "k / ↑", description: "Move up"),
                ShortcutInfo(key: "⇥", description: "Focus list (exit typing)"),
                ShortcutInfo(key: "⌃P", description: "Locate item in history"),
                ShortcutInfo(key: "⎋", description: "Exit search mode"),
            ]
        } else if !searchText.isEmpty {
            return [
                ShortcutInfo(key: kb.binding(for: .moveDown).displayString + " / ↓", description: "Move down"),
                ShortcutInfo(key: kb.binding(for: .moveUp).displayString + " / ↑", description: "Move up"),
                ShortcutInfo(key: kb.binding(for: .paste).displayString, description: "Paste selected item"),
                ShortcutInfo(key: kb.binding(for: .position).displayString, description: "Clear search & locate"),
                ShortcutInfo(key: kb.binding(for: .search).displayString, description: "Focus search"),
                ShortcutInfo(key: kb.binding(for: .escape).displayString, description: "Close popup"),
            ]
        } else {
            // NORMAL mode - use dynamic bindings from KeyBindingManager
            return [
                ShortcutInfo(key: kb.binding(for: .moveDown).displayString + " / ↓", description: "Move down"),
                ShortcutInfo(key: kb.binding(for: .moveUp).displayString + " / ↑", description: "Move up"),
                ShortcutInfo(key: kb.binding(for: .paste).displayString, description: "Paste selected item"),
                ShortcutInfo(key: "1-9", description: "Quick paste by number"),
                ShortcutInfo(key: kb.binding(for: .search).displayString, description: "Search / Focus input"),
                ShortcutInfo(key: kb.binding(for: .favorite).displayString, description: "Toggle favorite"),
                ShortcutInfo(key: kb.binding(for: .filterByType).displayString, description: "Filter by type"),
                ShortcutInfo(key: "⇧P", description: "Toggle pin"),
                ShortcutInfo(key: "t", description: "Tag item"),
                ShortcutInfo(key: "⇧T", description: "Open tag panel"),
                ShortcutInfo(key: kb.binding(for: .commandMenu).displayString, description: "Command menu"),
                ShortcutInfo(key: kb.binding(for: .quickPreview).displayString, description: "Preview item"),
                ShortcutInfo(key: "o", description: "Open in external app"),
                ShortcutInfo(key: kb.binding(for: .delete).displayString, description: "Delete item"),
                ShortcutInfo(key: kb.binding(for: .addToQueue).displayString, description: "Add to paste queue"),
                ShortcutInfo(key: kb.binding(for: .escape).displayString, description: "Close popup"),
                ShortcutInfo(key: "?", description: "Show this help"),
            ]
        }
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
                    Text("Filter by Type")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("ESC to close")
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
                            
                            Text(filter.rawValue)
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
                        Text("Navigate")
                            .font(.system(size: 10))
                    }
                    
                    HStack(spacing: 4) {
                        Text("⏎/␣")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(theme.tertiaryBackground)
                            .cornerRadius(3)
                        Text("Select")
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
                    Text("Tag Item")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("ESC to close")
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
                            Text("No tags yet. Press 'n' to create one.")
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
                                
                                TextField("New tag name...", text: $newTagNameInPopup)
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
                        Text("nav")
                            .font(.system(size: 10))
                    }
                    
                    HStack(spacing: 4) {
                        Text("␣")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(theme.tertiaryBackground)
                            .cornerRadius(3)
                        Text("toggle")
                            .font(.system(size: 10))
                    }
                    
                    HStack(spacing: 4) {
                        Text("n")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(theme.tertiaryBackground)
                            .cornerRadius(3)
                        Text("new")
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
    
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        
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
        
        // Enter key - paste selected (only in NORMAL mode, not SEARCH)
        if keyCode == 36 && !isSearchFocused {
            if let item = selectedItem {
                clipboardMonitor.paste(item: item)
            }
            return true
        }
        
        // Number keys for quick select (only in NORMAL mode)
        if !isSearchFocused, let num = keyBindingManager.quickSelectNumber(event) {
            let index = num - 1
            if index < filteredItems.count {
                selectedIndex = index
                if let item = selectedItem {
                    clipboardMonitor.paste(item: item)
                }
                return true
            }
        }
        
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
            // P key: works when searchText is not empty (filtered content)
            // Clears search and locates item in full history
            if !isSearchFocused && !searchText.isEmpty, let item = selectedItem {
                let targetId = item.originalId
                
                // Clear search and reset to first page
                searchText = ""
                clipboardMonitor.loadFirstPage()
                
                // Find and select the original item after list reloads
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let index = self.filteredItems.firstIndex(where: { $0.id == targetId }) {
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                            self.selectedIndex = index
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
             .previewHalfPageUp, .previewHalfPageDown, .previewOpenExternal:
            return false
            
        // Advanced filter - handled by keyboard shortcut directly
        case .advancedFilter:
            isAdvancedFilterOpen = true
            return true
        }
        
        return false
    }
    
    // MARK: - Type Filter Mode
    
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
                guard var item = result.item.toClipboardItem() else { return nil }
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
        } catch {
            print("Error loading pinned items: \(error)")
            pinnedItems = []
        }
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
        switch item.content {
        case .image:
            // Use separate window for images
            PreviewWindowController.shared.showPreview(for: item)
            
        case .fileURL(let path):
            // Use Quick Look for files
            QuickLookController.shared.showPreview(for: path)
            
        default:
            // Use in-app preview for text/RTF
            previewingItem = item
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
                    previewOCRResult = "OCR failed: \(error.localizedDescription)"
                    isPerformingOCR = false
                }
            }
        }
    }
    
    private func copyPreviewContent() {
        guard let item = previewingItem else { return }
        
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
    
    private func scrollPreview(by amount: CGFloat) {
        previewScrollOffset += amount
    }
    
    private func openInExternalApp(_ item: ClipboardItem) {
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
                    Text("Preview")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Spacer()
                    
                    // Open in external app button
                    Button(action: {
                        openInExternalApp(item)
                        exitPreviewMode()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Open")
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.tertiaryBackground)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    Text("? for shortcuts")
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryText)
                        .padding(.leading, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(theme.tertiaryBackground)
                
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
                        if SyntaxHighlighter.shared.isLikelyCode(displayText),
                           let highlighted = SyntaxHighlighter.shared.highlight(displayText) {
                            return highlighted
                        } else {
                            return NSAttributedString(string: displayText, attributes: [
                                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                                .foregroundColor: NSColor.textColor
                            ])
                        }
                    }()
                    
                    ScrollableTextView(
                        attributedText: attrString,
                        scrollOffset: $previewScrollOffset,
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
                            Text("Extracting text...")
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
                            Text("⌘C to copy")
                                .font(.system(size: 10))
                                .foregroundColor(theme.secondaryText)
                        } else {
                            Text("Press 'o' to extract text (OCR)")
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
                        Text("Copied!")
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
                Text("Unable to load image")
                    .foregroundColor(theme.secondaryText)
            }
            
        case .text(let text):
            VStack(alignment: .leading, spacing: 8) {
                // Check if it's a file path
                if isFilePath(text) {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(theme.accent)
                        Text("File Path")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.secondaryText)
                    }
                    .padding(.bottom, 4)
                }
                
                // Simple text display (no syntax highlighting for performance)
                // Full syntax highlighting is only in preview mode (v key)
                Text(text)
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
                                Text("Size")
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.secondaryText)
                            }
                        }
                        if let modDate = attrs[.modificationDate] as? Date {
                            VStack {
                                Text(modDate, style: .date)
                                    .font(.system(size: 14, weight: .medium))
                                Text("Modified")
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
                        Text(AttributedString(highlighted))
                            .font(.custom("Menlo", size: 12))
                            .padding(8)
                            .background(Color(red: 0.15, green: 0.16, blue: 0.18))
                            .cornerRadius(4)
                    } else {
                        Text(AttributedString(attrString))
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Unable to load rich text")
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
                Text(displayMode)
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
                    Text("Around: \(anchor.content.preview.prefix(20))...")
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
                
                TextField("Type to filter... (/ to search, : for commands)", text: $searchText)
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
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            } else {
                Button("Exit Position Mode") {
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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.displayId) { index, item in
                                // Show separator between pinned items and normal items
                                if index == pinnedItems.count && !pinnedItems.isEmpty {
                                    HStack {
                                        VStack { Divider() }
                                        Text("History")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(theme.secondaryText)
                                            .textCase(.uppercase)
                                        VStack { Divider() }
                                    }
                                    .padding(.vertical, 4)
                                }
                                
                                CompactItemRow(
                                    item: item,
                                    index: index,
                                    isSelected: index == selectedIndex,
                                    isFocused: !isTagPanelFocused,
                                    isAnchor: isPositionMode && item.id == positionAnchorItem?.id,
                                    isPinned: item.isPinnedItem,
                                    isInSearchMode: isSearchFocused,
                                    fontSize: themeManager.fontSize,
                                    theme: theme
                                )
                                .id(item.displayId)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = index
                                    isSearchFocused = false  // Back to NORMAL mode
                                }
                                .onTapGesture(count: 2) {
                                    clipboardMonitor.paste(item: item)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: selectedIndex) { newValue in
                        if let item = filteredItems[safe: newValue] {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(item.displayId, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .background(theme.background)
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch item.content {
                        case .text(let string):
                            // Async loading for large text to prevent UI blocking
                            if string.count > 5000 {
                                if isLoadingPreview && previewItemId == item.id {
                                    VStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading preview...")
                                            .font(.system(size: themeManager.fontSize))
                                            .foregroundColor(theme.secondaryText)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else if previewItemId == item.id, let text = previewText {
                                    Text(text)
                                        .font(.system(size: themeManager.previewFontSize, design: .monospaced))
                                        .foregroundColor(theme.text)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    // Trigger async load
                                    Color.clear.onAppear {
                                        loadPreviewAsync(for: item, text: string)
                                    }
                                }
                            } else {
                                // Small text, render directly
                                Text(string)
                                    .font(.system(size: themeManager.previewFontSize, design: .monospaced))
                                    .foregroundColor(theme.text)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                        case .richText(let data):
                            if let attrString = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                                Text(AttributedString(attrString))
                                    .font(.system(size: themeManager.previewFontSize))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                        case .image(let data):
                            if let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            
                        case .fileURL(let path):
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(theme.accent)
                                
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(.system(size: themeManager.previewFontSize, weight: .medium))
                                    .foregroundColor(theme.text)
                                
                                Text(path)
                                    .font(.system(size: themeManager.fontSize - 2))
                                    .foregroundColor(theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: selectedIndex) { _ in
                    // Reset preview when selection changes
                    previewItemId = nil
                    previewText = nil
                    isLoadingPreview = false
                }
            } else {
                VStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(theme.secondaryText.opacity(0.5))
                    Text("Select an item to preview")
                        .font(.system(size: themeManager.fontSize))
                        .foregroundColor(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
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
                ? String(text.prefix(maxChars)) + "\n\n... (\(text.count - maxChars) more characters)" 
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
                Text("Information")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.secondaryText)
                
                Spacer()
                
                // Quick actions
                if selectedItem != nil {
                    Button(action: { enterCommandMode() }) {
                        HStack(spacing: 2) {
                            Text(":")
                                .font(.system(size: 10, design: .monospaced))
                            Text("Actions")
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
                    InfoRow(label: "Application", value: item.sourceApp ?? "Unknown", theme: theme, fontSize: themeManager.fontSize)
                    InfoRow(label: "Content type", value: item.content.typeName, theme: theme, fontSize: themeManager.fontSize)
                    InfoRow(label: "Copied at", value: formatDate(item.createdAt), theme: theme, fontSize: themeManager.fontSize)
                    InfoRow(label: "Position", value: "#\(item.position)", theme: theme, fontSize: themeManager.fontSize)
                    
                    // Image-specific info
                    if case .image(let data) = item.content {
                        if let nsImage = NSImage(data: data) {
                            InfoRow(label: "Resolution", value: "\(Int(nsImage.size.width))×\(Int(nsImage.size.height))", theme: theme, fontSize: themeManager.fontSize)
                        }
                        InfoRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file), theme: theme, fontSize: themeManager.fontSize)
                    }
                    
                    // Text character count
                    if case .text(let string) = item.content {
                        InfoRow(label: "Characters", value: "\(string.count)", theme: theme, fontSize: themeManager.fontSize)
                    }
                    
                    // File-specific info
                    if case .fileURL(let path) = item.content {
                        let fileInfo = getFileInfo(path: path)
                        if let size = fileInfo.size {
                            InfoRow(label: "File size", value: size, theme: theme, fontSize: themeManager.fontSize)
                        }
                        if let modified = fileInfo.modified {
                            InfoRow(label: "Modified", value: modified, theme: theme, fontSize: themeManager.fontSize)
                        }
                    }
                    
                    // PIN status display
                    if item.isDirectPinned || item.isPinnedItem {
                        HStack {
                            Text("PIN Status")
                                .font(.system(size: themeManager.fontSize - 1))
                                .foregroundColor(theme.secondaryText)
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 10))
                                let (statusText, statusColor): (String, Color) = {
                                    switch item.pinType {
                                    case .direct: return ("Direct", .orange)
                                    case .tag: return ("Tag", .blue)
                                    case .both: return ("Direct + Tag", .purple)
                                    case .none: return (item.isDirectPinned ? "Direct" : "Pinned", .orange)
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
                Text("No item selected")
                    .font(.system(size: themeManager.fontSize))
                    .foregroundColor(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(height: 180)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clipboard")
                .font(.system(size: 48))
                .foregroundColor(theme.secondaryText)
            
            Text(showFavoritesOnly ? "No favorites yet" : "Clipboard is empty")
                .font(.system(size: themeManager.fontSize + 2, weight: .medium))
                .foregroundColor(theme.secondaryText)
            
            Text("Copied items will appear here")
                .font(.system(size: themeManager.fontSize))
                .foregroundColor(theme.secondaryText.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundColor(theme.accent)
                Text("\(selectedIndex + 1) / \(clipboardMonitor.itemCount)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.secondaryText)
            }
            
            Spacer()
            
            // VIM hints
            HStack(spacing: 8) {
                KeyHint(key: "j/k", action: "nav", theme: theme)
                KeyHint(key: "⏎", action: "paste", theme: theme)
                KeyHint(key: "p", action: "locate", theme: theme)
                KeyHint(key: ":", action: "menu", theme: theme)
                KeyHint(key: "/", action: "search", theme: theme)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
            if isAnchor {
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
            } else if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 18)
            } else {
                Spacer()
                    .frame(width: 18)
            }
            
            // Icon
            itemIcon
                .frame(width: 24, height: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(item.content.preview)
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
                Text("ANCHOR")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan)
                    .cornerRadius(4)
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
            if let thumbnail = ThumbnailService.shared.thumbnail(for: data, id: item.id.uuidString) {
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
            return "Plain Text"
        case .richText:
            return "Rich Text (Formatted)"
        case .image:
            return "Image"
        case .fileURL:
            return "File Reference"
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
                Text("Tags")
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
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Update container width to match scroll view
        textView.textContainer?.size = NSSize(
            width: scrollView.contentSize.width - 24,  // Account for insets
            height: CGFloat.greatestFiniteMagnitude
        )
        
        // Update text content if changed
        if textView.textStorage?.string != attributedText.string {
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
        
        // Apply scroll offset
        let contentHeight = textView.frame.height
        let visibleHeight = scrollView.contentSize.height
        let maxScroll = max(0, contentHeight - visibleHeight)
        let clampedOffset = min(max(0, scrollOffset), maxScroll)
        
        let clipView = scrollView.contentView
        let newOrigin = NSPoint(x: 0, y: clampedOffset)
        if clipView.bounds.origin.y != clampedOffset {
            clipView.setBoundsOrigin(newOrigin)
        }
    }
}

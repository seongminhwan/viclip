import SwiftUI
import AppKit

struct AdvancedFilterView: View {
    @ObservedObject private var clipboardMonitor = ClipboardMonitor.shared
    @ObservedObject private var tagService = TagService.shared
    
    @Binding var filter: FilterQuery
    @Binding var isPresented: Bool
    
    @State private var availableSourceApps: [String] = []
    @State private var expandedSection: FilterSection? = .keyword
    
    // Selection indices for j/k navigation
    @State private var contentTypeIndex: Int = 0
    @State private var sourceAppIndex: Int = 0
    @State private var tagIndex: Int = 0
    @State private var timeRangeIndex: Int = 0
    @State private var optionsIndex: Int = 0
    
    // Focus states
    @FocusState private var isKeywordFocused: Bool
    @FocusState private var isFromDateFocused: Bool
    @FocusState private var isToDateFocused: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var theme: ThemeColors { ThemeColors.forScheme(colorScheme) }
    
    enum FilterSection: String, CaseIterable {
        case keyword, contentType, sourceApp, timeRange, tags, options
        
        var shortcut: String {
            switch self {
            case .keyword: return "⌘K"
            case .contentType: return "⌘C"
            case .sourceApp: return "⌘S"
            case .timeRange: return "⌘D"
            case .tags: return "⌘T"
            case .options: return "⌘O"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    keywordSection
                    sectionDivider
                    contentTypeSection
                    sectionDivider
                    sourceAppSection
                    sectionDivider
                    timeRangeSection
                    sectionDivider
                    tagsSection
                    sectionDivider
                    optionsSection
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            footerView
        }
        .frame(width: 480)
        .frame(maxHeight: 600)
        .background(KeyEventHandlingView(onKeyDown: handleKeyDown))
        .background(theme.background)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.4), radius: 30)
        .onAppear {
            loadSourceApps()
            // Auto-focus keyword input when panel opens
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isKeywordFocused = true
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundColor(theme.accent)
                .font(.system(size: 18))
            
            Text("Advanced Filter")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.text)
            
            Spacer()
            
            if filter.isActive {
                Text("\(countActiveFilters()) filters")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.accent)
                    .cornerRadius(4)
            }
            
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(theme.secondaryText)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(theme.secondaryBackground)
    }
    
    private var sectionDivider: some View {
        Divider().padding(.horizontal, 20)
    }
    
    // MARK: - Keyboard Handling
    
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let hasCmd = event.modifierFlags.contains(.command)
        let hasCtrl = event.modifierFlags.contains(.control)
        
        // ESC to close
        if keyCode == 53 {
            isPresented = false
            return true
        }
        
        // Global shortcuts (⌘) - TOGGLE sections
        if hasCmd {
            switch keyCode {
            case 40:  // ⌘K - Keyword toggle
                toggleSection(.keyword)
                if expandedSection == .keyword { isKeywordFocused = true }
                return true
            case 8:   // ⌘C - Content Type toggle
                toggleSection(.contentType)
                return true
            case 1:   // ⌘S - Source App toggle
                toggleSection(.sourceApp)
                return true
            case 17:  // ⌘T - Tags toggle
                toggleSection(.tags)
                return true
            case 2:   // ⌘D - Date Range toggle
                toggleSection(.timeRange)
                return true
            case 31:  // ⌘O - Options toggle
                toggleSection(.options)
                return true
            case 15:  // ⌘R - Reset
                filter.reset()
                return true
            case 36:  // ⌘↩ - Apply
                applyFilter()
                return true
            default:
                break
            }
        }
        
        // Section-specific shortcuts
        if let section = expandedSection {
            // Keyword section: Ctrl shortcuts
            if section == .keyword && hasCtrl {
                switch keyCode {
                case 15:  // ⌃R - Toggle Regex
                    filter.isRegex.toggle()
                    return true
                case 8:   // ⌃C - Toggle Case Sensitive
                    filter.caseSensitive.toggle()
                    return true
                default:
                    break
                }
            }
            
            // Time Range section: Ctrl shortcuts for presets + date focus
            if section == .timeRange && hasCtrl {
                switch keyCode {
                case 0:   // ⌃A - All Time
                    filter.timeRangePreset = .all
                    updateTimeRangeIndex()
                    return true
                case 37:  // ⌃L - Last Hour
                    filter.timeRangePreset = .lastHour
                    updateTimeRangeIndex()
                    return true
                case 17:  // ⌃T - Today (also To date when custom)
                    if filter.timeRangePreset == .custom {
                        isToDateFocused = true
                    } else {
                        filter.timeRangePreset = .today
                        updateTimeRangeIndex()
                    }
                    return true
                case 16:  // ⌃Y - Yesterday
                    filter.timeRangePreset = .yesterday
                    updateTimeRangeIndex()
                    return true
                case 13:  // ⌃W - Last 7 Days
                    filter.timeRangePreset = .last7Days
                    updateTimeRangeIndex()
                    return true
                case 46:  // ⌃M - Last 30 Days
                    filter.timeRangePreset = .last30Days
                    updateTimeRangeIndex()
                    return true
                case 3:   // ⌃F - From date focus (when custom)
                    if filter.timeRangePreset == .custom {
                        isFromDateFocused = true
                    }
                    return true
                case 8:   // ⌃C - Custom Range
                    filter.timeRangePreset = .custom
                    updateTimeRangeIndex()
                    return true
                default:
                    break
                }
            }
            
            // j/k navigation for list sections (including timeRange now)
            if section == .contentType || section == .sourceApp || section == .tags || section == .timeRange || section == .options {
                // j - down
                if keyCode == 38 {
                    moveSelectionDown(section)
                    return true
                }
                // k - up
                if keyCode == 40 {
                    moveSelectionUp(section)
                    return true
                }
                // Space - toggle selection
                if keyCode == 49 {
                    toggleCurrentSelection(section)
                    return true
                }
            }
        }
        
        return false
    }
    
    private func toggleSection(_ section: FilterSection) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSection == section {
                expandedSection = nil
            } else {
                expandedSection = section
                // Reset index when opening
                switch section {
                case .contentType: contentTypeIndex = 0
                case .sourceApp: sourceAppIndex = 0
                case .tags: tagIndex = 0
                case .timeRange: updateTimeRangeIndex()
                case .options: optionsIndex = 0
                default: break
                }
            }
        }
    }
    
    private func updateTimeRangeIndex() {
        if let index = TimeRangePreset.allCases.firstIndex(of: filter.timeRangePreset) {
            timeRangeIndex = index
        }
    }
    
    private func moveSelectionDown(_ section: FilterSection) {
        switch section {
        case .contentType:
            if contentTypeIndex < ContentTypeFilter.allCases.count - 1 {
                contentTypeIndex += 1
            }
        case .sourceApp:
            let maxIndex = availableSourceApps.count  // +1 for "All Apps" but 0-indexed
            if sourceAppIndex < maxIndex {
                sourceAppIndex += 1
            }
        case .tags:
            if tagIndex < tagService.tags.count - 1 {
                tagIndex += 1
            }
        case .timeRange:
            if timeRangeIndex < TimeRangePreset.allCases.count - 1 {
                timeRangeIndex += 1
            }
        case .options:
            // Only 1 option for now
            break
        default:
            break
        }
    }
    
    private func moveSelectionUp(_ section: FilterSection) {
        switch section {
        case .contentType:
            if contentTypeIndex > 0 { contentTypeIndex -= 1 }
        case .sourceApp:
            if sourceAppIndex > 0 { sourceAppIndex -= 1 }
        case .tags:
            if tagIndex > 0 { tagIndex -= 1 }
        case .timeRange:
            if timeRangeIndex > 0 { timeRangeIndex -= 1 }
        case .options:
            break
        default:
            break
        }
    }
    
    private func toggleCurrentSelection(_ section: FilterSection) {
        switch section {
        case .contentType:
            let types = Array(ContentTypeFilter.allCases)
            guard contentTypeIndex < types.count else { return }
            let type = types[contentTypeIndex]
            if filter.contentTypes.contains(type) {
                filter.contentTypes.remove(type)
            } else {
                filter.contentTypes.insert(type)
            }
        case .sourceApp:
            if sourceAppIndex == 0 {
                filter.sourceApps = []  // All Apps
            } else {
                let appIndex = sourceAppIndex - 1
                guard appIndex < availableSourceApps.count else { return }
                let app = availableSourceApps[appIndex]
                if filter.sourceApps.contains(app) {
                    filter.sourceApps.removeAll { $0 == app }
                } else {
                    filter.sourceApps.append(app)
                }
            }
        case .tags:
            guard tagIndex < tagService.tags.count else { return }
            let tag = tagService.tags[tagIndex]
            if filter.tagIds.contains(tag.id) {
                filter.tagIds.removeAll { $0 == tag.id }
            } else {
                filter.tagIds.append(tag.id)
            }
        case .timeRange:
            // TimeRange is single-select
            let presets = Array(TimeRangePreset.allCases)
            guard timeRangeIndex < presets.count else { return }
            filter.timeRangePreset = presets[timeRangeIndex]
        case .options:
            filter.favoritesOnly.toggle()
        default:
            break
        }
    }
    
    // MARK: - Section Header
    
    @ViewBuilder
    private func sectionHeader(_ section: FilterSection, title: String, icon: String, summary: String) -> some View {
        Button(action: { toggleSection(section) }) {
            HStack {
                Image(systemName: expandedSection == section ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 16)
                
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(theme.accent)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.text)
                
                Text(section.shortcut)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.secondaryText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(theme.tertiaryBackground)
                    .cornerRadius(3)
                
                Spacer()
                
                if expandedSection != section {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 150, alignment: .trailing)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Keyword Section
    
    private var keywordSection: some View {
        VStack(spacing: 0) {
            sectionHeader(.keyword, title: "Keyword", icon: "magnifyingglass",
                         summary: filter.keyword.isEmpty ? "None" : "\"\(filter.keyword.prefix(20))\"")
            
            if expandedSection == .keyword {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Search text...", text: $filter.keyword)
                            .textFieldStyle(.roundedBorder)
                            .focused($isKeywordFocused)
                        
                        if !filter.keyword.isEmpty {
                            Button(action: { filter.keyword = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(theme.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Toggle("", isOn: $filter.isRegex)
                                .toggleStyle(.checkbox)
                            Text("Regex")
                            Text("⌃R")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(theme.secondaryText)
                        }
                        
                        HStack(spacing: 4) {
                            Toggle("", isOn: $filter.caseSensitive)
                                .toggleStyle(.checkbox)
                            Text("Case Sensitive")
                            Text("⌃C")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(theme.secondaryText)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(theme.text)
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 12)
            }
        }
    }
    
    // MARK: - Content Type Section
    
    private var contentTypeSummary: String {
        let count = filter.contentTypes.count
        if count == ContentTypeFilter.allCases.count { return "All" }
        if count == 0 { return "None" }
        return filter.contentTypes.map { $0.displayName }.prefix(3).joined(separator: ", ")
    }
    
    private var contentTypeSection: some View {
        VStack(spacing: 0) {
            sectionHeader(.contentType, title: "Content Type", icon: "doc.on.doc",
                         summary: contentTypeSummary)
            
            if expandedSection == .contentType {
                VStack(spacing: 0) {
                    ForEach(Array(ContentTypeFilter.allCases.enumerated()), id: \.element.id) { index, type in
                        SelectableRow(
                            icon: type.icon,
                            title: type.displayName,
                            isSelected: filter.contentTypes.contains(type),
                            isHighlighted: contentTypeIndex == index,
                            theme: theme
                        ) {
                            contentTypeIndex = index
                            if filter.contentTypes.contains(type) {
                                filter.contentTypes.remove(type)
                            } else {
                                filter.contentTypes.insert(type)
                            }
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 8)
            }
        }
    }
    
    // MARK: - Source App Section
    
    private var sourceAppSummary: String {
        if filter.sourceApps.isEmpty { return "All Apps" }
        return filter.sourceApps.prefix(2).joined(separator: ", ")
    }
    
    private var sourceAppSection: some View {
        VStack(spacing: 0) {
            sectionHeader(.sourceApp, title: "Source App", icon: "app.badge",
                         summary: sourceAppSummary)
            
            if expandedSection == .sourceApp {
                VStack(spacing: 0) {
                    if availableSourceApps.isEmpty {
                        Text("No source apps recorded")
                            .font(.system(size: 12))
                            .foregroundColor(theme.secondaryText)
                            .padding(.vertical, 8)
                    } else {
                        // All Apps option (radio-style when selected, clears others)
                        SelectableRow(
                            title: "All Apps",
                            isSelected: filter.sourceApps.isEmpty,
                            isHighlighted: sourceAppIndex == 0,
                            theme: theme
                        ) {
                            sourceAppIndex = 0
                            filter.sourceApps = []
                        }
                        
                        ForEach(Array(availableSourceApps.enumerated()), id: \.element) { index, app in
                            SelectableRow(
                                title: app,
                                isSelected: filter.sourceApps.contains(app),
                                isHighlighted: sourceAppIndex == index + 1,
                                theme: theme
                            ) {
                                sourceAppIndex = index + 1
                                if filter.sourceApps.contains(app) {
                                    filter.sourceApps.removeAll { $0 == app }
                                } else {
                                    filter.sourceApps.append(app)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 8)
            }
        }
    }
    
    // MARK: - Time Range Section (Single Select with j/k)
    
    private var timeRangeSection: some View {
        VStack(spacing: 0) {
            sectionHeader(.timeRange, title: "Time Range", icon: "clock",
                         summary: filter.timeRangePreset.displayName)
            
            if expandedSection == .timeRange {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(TimeRangePreset.allCases.enumerated()), id: \.element.id) { index, preset in
                        let shortcut = timeRangeShortcut(preset)
                        RadioRow(
                            title: preset.displayName,
                            shortcut: shortcut,
                            isSelected: filter.timeRangePreset == preset,
                            isHighlighted: timeRangeIndex == index,
                            theme: theme
                        ) {
                            timeRangeIndex = index
                            filter.timeRangePreset = preset
                        }
                    }
                    
                    if filter.timeRangePreset == .custom {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("From")
                                    Text("⌃F")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(theme.secondaryText)
                                }
                                .font(.system(size: 11)).foregroundColor(theme.secondaryText)
                                DatePicker("", selection: Binding(
                                    get: { filter.customDateFrom ?? Date() },
                                    set: { filter.customDateFrom = $0 }
                                ), displayedComponents: [.date])
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .focused($isFromDateFocused)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("To")
                                    Text("⌃T")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(theme.secondaryText)
                                }
                                .font(.system(size: 11)).foregroundColor(theme.secondaryText)
                                DatePicker("", selection: Binding(
                                    get: { filter.customDateTo ?? Date() },
                                    set: { filter.customDateTo = $0 }
                                ), displayedComponents: [.date])
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .focused($isToDateFocused)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 8)
            }
        }
    }
    
    private func timeRangeShortcut(_ preset: TimeRangePreset) -> String {
        switch preset {
        case .all: return "⌃A"
        case .lastHour: return "⌃L"
        case .today: return "⌃T"
        case .yesterday: return "⌃Y"
        case .last7Days: return "⌃W"
        case .last30Days: return "⌃M"
        case .custom: return "⌃C"
        }
    }
    
    // MARK: - Tags Section
    
    private var tagsSummary: String {
        if filter.tagIds.isEmpty { return "All" }
        let names = filter.tagIds.compactMap { id in
            tagService.tags.first { $0.id == id }?.name
        }
        return names.prefix(2).joined(separator: ", ")
    }
    
    private var tagsSection: some View {
        VStack(spacing: 0) {
            sectionHeader(.tags, title: "Tags", icon: "tag", summary: tagsSummary)
            
            if expandedSection == .tags {
                VStack(spacing: 0) {
                    if tagService.tags.isEmpty {
                        Text("No tags available")
                            .font(.system(size: 12))
                            .foregroundColor(theme.secondaryText)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(tagService.tags.enumerated()), id: \.element.id) { index, tag in
                            SelectableRow(
                                color: tag.color.flatMap { Color(hex: $0) },
                                title: tag.name,
                                isSelected: filter.tagIds.contains(tag.id),
                                isHighlighted: tagIndex == index,
                                theme: theme
                            ) {
                                tagIndex = index
                                if filter.tagIds.contains(tag.id) {
                                    filter.tagIds.removeAll { $0 == tag.id }
                                } else {
                                    filter.tagIds.append(tag.id)
                                }
                            }
                        }
                        
                        if !filter.tagIds.isEmpty {
                            HStack(spacing: 12) {
                                Text("Match:")
                                    .font(.system(size: 11))
                                    .foregroundColor(theme.secondaryText)
                                
                                Picker("", selection: $filter.tagMatchMode) {
                                    Text("Any").tag(TagMatchMode.any)
                                    Text("All").tag(TagMatchMode.all)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 8)
            }
        }
    }
    
    // MARK: - Options Section (Checkbox List)
    
    private var optionsSection: some View {
        VStack(spacing: 0) {
            sectionHeader(.options, title: "Options", icon: "slider.horizontal.3",
                         summary: filter.favoritesOnly ? "Favorites Only" : "None")
            
            if expandedSection == .options {
                VStack(spacing: 0) {
                    SelectableRow(
                        icon: "star.fill",
                        title: "Favorites Only",
                        isSelected: filter.favoritesOnly,
                        isHighlighted: optionsIndex == 0,
                        theme: theme
                    ) {
                        optionsIndex = 0
                        filter.favoritesOnly.toggle()
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 8)
            }
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack(spacing: 12) {
            Button(action: { filter.reset() }) {
                HStack {
                    Text("Reset")
                    Text("⌘R")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.secondaryText)
                }
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(theme.tertiaryBackground)
                .foregroundColor(theme.text)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Button(action: { applyFilter() }) {
                HStack {
                    Text("Apply Filter")
                    Text("⌘↩")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(theme.accent)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(theme.secondaryBackground)
    }
    
    // MARK: - Helpers
    
    private func loadSourceApps() {
        availableSourceApps = clipboardMonitor.getDistinctSourceApps()
    }
    
    private func applyFilter() {
        clipboardMonitor.setAdvancedFilter(filter.isActive ? filter : nil)
        isPresented = false
    }
    
    private func countActiveFilters() -> Int {
        var count = 0
        if !filter.keyword.isEmpty { count += 1 }
        if filter.contentTypes.count < ContentTypeFilter.allCases.count { count += 1 }
        if !filter.sourceApps.isEmpty { count += 1 }
        if filter.timeRangePreset != .all { count += 1 }
        if !filter.tagIds.isEmpty { count += 1 }
        if filter.favoritesOnly { count += 1 }
        return count
    }
}

// MARK: - Selectable Row (Checkbox style, multi-select)

struct SelectableRow: View {
    var icon: String? = nil
    var color: Color? = nil
    let title: String
    var shortcut: String? = nil
    let isSelected: Bool
    let isHighlighted: Bool
    let theme: ThemeColors
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? theme.accent : theme.secondaryText)
                
                // Color dot (for tags)
                if let color = color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                
                // Icon (for content types)
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(theme.secondaryText)
                }
                
                // Title
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(theme.text)
                
                Spacer()
                
                // Shortcut hint
                if let shortcut = shortcut, !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.secondaryText)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(theme.tertiaryBackground)
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHighlighted ? theme.selection : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Radio Row (Single select)

struct RadioRow: View {
    let title: String
    var shortcut: String? = nil
    let isSelected: Bool
    let isHighlighted: Bool
    let theme: ThemeColors
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Radio button
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? theme.accent : theme.secondaryText)
                
                // Title
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(theme.text)
                
                Spacer()
                
                // Shortcut hint
                if let shortcut = shortcut, !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.secondaryText)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(theme.tertiaryBackground)
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHighlighted ? theme.selection : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

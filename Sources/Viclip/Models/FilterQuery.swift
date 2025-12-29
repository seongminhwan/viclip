import Foundation

// MARK: - Content Type Filter
enum ContentTypeFilter: String, CaseIterable, Identifiable {
    case text = "text"
    case richText = "richText"
    case image = "image"
    case fileURL = "fileURL"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .fileURL: return "File"
        }
    }
    
    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .fileURL: return "folder"
        }
    }
}

// MARK: - Tag Match Mode
enum TagMatchMode: String, CaseIterable {
    case any = "any"
    case all = "all"
    
    var displayName: String {
        switch self {
        case .any: return "Match Any"
        case .all: return "Match All"
        }
    }
}

// MARK: - Time Range Preset
enum TimeRangePreset: String, CaseIterable, Identifiable {
    case all = "all"
    case lastHour = "lastHour"
    case today = "today"
    case yesterday = "yesterday"
    case last7Days = "last7Days"
    case last30Days = "last30Days"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .all: return "All Time"
        case .lastHour: return "Last Hour"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .custom: return "Custom Range"
        }
    }
    
    var dateRange: (from: Date?, to: Date?) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .all:
            return (nil, nil)
        case .lastHour:
            return (calendar.date(byAdding: .hour, value: -1, to: now), nil)
        case .today:
            return (calendar.startOfDay(for: now), nil)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            return (calendar.startOfDay(for: yesterday), calendar.startOfDay(for: now))
        case .last7Days:
            return (calendar.date(byAdding: .day, value: -7, to: now), nil)
        case .last30Days:
            return (calendar.date(byAdding: .day, value: -30, to: now), nil)
        case .custom:
            return (nil, nil)  // User sets manually
        }
    }
}

// MARK: - Filter Query
struct FilterQuery: Equatable {
    // Keyword search
    var keyword: String = ""
    var isRegex: Bool = false
    var caseSensitive: Bool = false
    
    // Content type filter
    var contentTypes: Set<ContentTypeFilter> = Set(ContentTypeFilter.allCases)
    
    // Source app filter
    var sourceApps: [String] = []  // Empty means all apps
    var sourceBundleIds: [String] = []
    
    // Time range
    var timeRangePreset: TimeRangePreset = .all
    var customDateFrom: Date?
    var customDateTo: Date?
    
    // Tags
    var tagIds: [String] = []
    var tagMatchMode: TagMatchMode = .any
    
    // Favorites only
    var favoritesOnly: Bool = false
    
    // Computed: effective date range
    var effectiveDateRange: (from: Date?, to: Date?) {
        if timeRangePreset == .custom {
            return (customDateFrom, customDateTo)
        }
        return timeRangePreset.dateRange
    }
    
    // Check if filter is active (has any non-default values)
    var isActive: Bool {
        !keyword.isEmpty ||
        contentTypes.count != ContentTypeFilter.allCases.count ||
        !sourceApps.isEmpty ||
        timeRangePreset != .all ||
        !tagIds.isEmpty ||
        favoritesOnly
    }
    
    // Reset to defaults
    mutating func reset() {
        keyword = ""
        isRegex = false
        caseSensitive = false
        contentTypes = Set(ContentTypeFilter.allCases)
        sourceApps = []
        sourceBundleIds = []
        timeRangePreset = .all
        customDateFrom = nil
        customDateTo = nil
        tagIds = []
        tagMatchMode = .any
        favoritesOnly = false
    }
    
    // Create empty filter
    static var empty: FilterQuery {
        FilterQuery()
    }
}

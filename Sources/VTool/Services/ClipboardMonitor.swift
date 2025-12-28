import Foundation
import AppKit
import Combine

class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()
    
    @Published var items: [ClipboardItem] = []
    @Published var favoriteGroups: [FavoriteGroup] = []
    @Published var searchResults: [ClipboardItem] = []
    @Published var isSearching: Bool = false
    
    // Pagination
    private let pageSize = 100
    private var currentPage = 0
    private var hasMoreItems = true
    
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var positionCounter: Int = 0
    private let store: ClipboardStore
    private let privacyFilter: PrivacyFilter
    private let storageSettings = StorageSettings.shared
    
    // Common password manager bundle IDs
    private let defaultExcludedApps: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.lastpass.LastPass",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess"
    ]
    
    private init() {
        store = ClipboardStore()
        privacyFilter = PrivacyFilter()
        loadData()
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        // Get source app
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let appName = sourceApp?.localizedName
        let bundleId = sourceApp?.bundleIdentifier
        
        // Check privacy filter
        if let bundleId = bundleId, privacyFilter.shouldExclude(bundleId: bundleId) {
            return
        }
        
        // Extract content
        guard let content = extractContent(from: pasteboard) else { return }
        
        // Check for duplicate (same content consecutively)
        if let lastItem = items.first, lastItem.content == content {
            return
        }
        
        // Check keyword filter
        if case .text(let text) = content, privacyFilter.shouldExclude(text: text) {
            return
        }
        
        // Create new item
        positionCounter += 1
        let newItem = ClipboardItem(
            content: content,
            sourceApp: appName,
            sourceAppBundleId: bundleId,
            position: positionCounter
        )
        
        // Add to beginning of in-memory list
        items.insert(newItem, at: 0)
        
        // Limit in-memory history to prevent memory issues
        // Database stores all items, but memory only keeps recent ones for fast access
        let maxInMemory = 500
        if items.count > maxInMemory {
            items = Array(items.prefix(maxInMemory))
        }
        
        // Save to database
        store.saveItem(newItem)
    }
    
    private func extractContent(from pasteboard: NSPasteboard) -> ClipboardContent? {
        // Try file URL first (before text, since file copies also include filename as text)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first, firstURL.isFileURL {
            return .fileURL(firstURL.path)
        }
        
        // Try image
        if let imageData = pasteboard.data(forType: .png) {
            return .image(imageData)
        }
        if let imageData = pasteboard.data(forType: .tiff) {
            // Convert TIFF to PNG for storage
            if let image = NSImage(data: imageData),
               let pngData = image.pngData() {
                return .image(pngData)
            }
        }
        
        // Try RTF
        if let rtfData = pasteboard.data(forType: .rtf) {
            return .richText(rtfData)
        }
        
        // Try text last
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return .text(string)
        }
        
        return nil
    }
    
    // MARK: - Actions
    
    func paste(item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .richText(let data):
            pasteboard.setData(data, forType: .rtf)
        case .image(let data):
            pasteboard.setData(data, forType: .png)
        case .fileURL(let path):
            let url = URL(fileURLWithPath: path)
            pasteboard.writeObjects([url as NSURL])
            // Also set as text for text editors
            pasteboard.setString(path, forType: .string)
        }
        
        // Update change count to ignore this clipboard change
        lastChangeCount = NSPasteboard.general.changeCount
        
        // Close popover and paste to previous app
        AppDelegate.shared?.closePopoverAndPaste()
    }
    
    func delete(item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        store.deleteItem(id: item.id)
    }
    
    func toggleFavorite(item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isFavorite.toggle()
            store.updateItem(items[index])
        }
    }
    
    func togglePin(item: ClipboardItem) {
        // Use originalId for pinned virtual items
        let targetId = item.originalId
        if let index = items.firstIndex(where: { $0.id == targetId }) {
            items[index].isDirectPinned.toggle()
            store.updateItem(items[index])
        }
    }
    
    func clearHistory() {
        let favoritesToKeep = items.filter { $0.isFavorite }
        items = favoritesToKeep
        // Note: This should also clear non-favorites from database
        // For now, just update in-memory
    }
    
    // MARK: - Unified Pagination with Optional Search
    
    /// Current search query (nil = browse all)
    private(set) var currentQuery: String? = nil
    
    /// Current tag IDs filter (empty = no filter)
    private(set) var currentTagIds: [String] = []
    
    /// Current page offset (for tracking position in database)
    private(set) var currentOffset: Int = 0
    
    /// Whether there are more items to load
    @Published private(set) var hasMore: Bool = true
    
    /// Set search query and/or tag filter, then reload items
    func setSearchQuery(_ query: String?, tagIds: [String]? = nil) {
        let trimmedQuery = query?.trimmingCharacters(in: .whitespaces)
        currentQuery = (trimmedQuery?.isEmpty ?? true) ? nil : trimmedQuery
        currentTagIds = tagIds ?? []
        currentOffset = 0
        hasMore = true  // Reset
        
        let loadedItems = store.loadItems(limit: 100, offset: 0, query: currentQuery, tagIds: currentTagIds.isEmpty ? nil : currentTagIds)
        items = loadedItems
        
        // If loaded less than page size, no more items
        if loadedItems.count < 100 {
            hasMore = false
        }
    }
    
    /// Load more items (next page)
    func loadMore() {
        // Skip if no more items
        guard hasMore else { return }
        
        let offset = items.count
        let moreItems = store.loadItems(limit: 100, offset: offset, query: currentQuery, tagIds: currentTagIds.isEmpty ? nil : currentTagIds)
        
        // If got less than page size, no more items
        if moreItems.count < 100 {
            hasMore = false
        }
        
        // Filter out duplicates
        let existingIds = Set(items.map { $0.id })
        let newItems = moreItems.filter { !existingIds.contains($0.id) }
        
        if !newItems.isEmpty {
            items.append(contentsOf: newItems)
        } else {
            // No new items, definitely no more
            hasMore = false
        }
    }
    
    /// Load the last page of items (for wrap-around from first to last)
    /// Returns the index of the last item
    func loadLastPage() -> Int {
        let total = currentQuery == nil ? itemCount : items.count + 100  // Estimate for search
        if total == 0 { return 0 }
        
        let pageSize = 100
        
        // For search, we need to get total count first (expensive for LIKE)
        // For now, just load from a high offset and adjust
        if currentQuery != nil {
            // For search results, try to load "last" by getting more results
            let lastPageItems = store.loadItems(limit: pageSize, offset: max(0, items.count), query: currentQuery)
            if !lastPageItems.isEmpty {
                items.append(contentsOf: lastPageItems)
            }
            return items.count - 1
        }
        
        // For normal browsing
        let lastPageOffset = max(0, total - pageSize)
        items = store.loadItems(limit: pageSize, offset: lastPageOffset, query: nil)
        currentOffset = lastPageOffset
        
        return items.count - 1
    }
    
    /// Load the first page of items (for wrap-around from last to first)
    func loadFirstPage() {
        currentOffset = 0
        items = store.loadItems(limit: 100, offset: 0, query: currentQuery)
    }
    
    /// Load previous page (for navigating up)
    /// Returns true if there was a previous page to load
    func loadPreviousPage() -> Bool {
        if currentOffset <= 0 { return false }
        
        let pageSize = 100
        let newOffset = max(0, currentOffset - pageSize)
        
        let prevItems = store.loadItems(limit: pageSize, offset: newOffset, query: currentQuery)
        
        // Prepend previous page items
        items = prevItems + items
        currentOffset = newOffset
        
        return true
    }
    
    // MARK: - Persistence
    
    private func loadData() {
        items = store.loadItems(limit: 100, offset: 0)
        favoriteGroups = store.loadGroups()
        // Use MAX position from database to prevent unique constraint errors
        positionCounter = store.maxPosition()
    }
    
    func reloadFromDatabase() {
        items = store.loadItems(limit: 100, offset: 0)
    }
    
    // MARK: - Statistics
    
    var itemCount: Int {
        store.itemCount()
    }
    
    var totalSize: Int64 {
        store.totalSize()
    }
    
    var externalFileCount: Int {
        store.externalFileCount()
    }
}

// MARK: - NSImage Extension
extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

import Foundation
import AppKit
import Combine

class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()

    @Published var items: [ClipboardItem] = []
    @Published var favoriteGroups: [FavoriteGroup] = []
    @Published var searchResults: [ClipboardItem] = []
    @Published var isSearching: Bool = false
    @Published var activeFilter: FilterQuery?  // Advanced filter state

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
    private var contentCache: [UUID: ClipboardItem] = [:]
    private var contentCacheOrder: [UUID] = []
    private let maxContentCacheCount = 64

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
        guard let item = fullItem(for: item) else { return }

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

    /// Paste as plain text, stripping any formatting
    func pasteAsPlainText(item: ClipboardItem) {
        guard let item = fullItem(for: item) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Extract plain text from any content type
        let plainText: String
        switch item.content {
        case .text(let string):
            plainText = string
        case .richText(let data):
            // Convert RTF to plain text
            if let attributedString = NSAttributedString(rtf: data, documentAttributes: nil) {
                plainText = attributedString.string
            } else {
                plainText = ""
            }
        case .image:
            // Cannot paste image as plain text
            return
        case .fileURL(let path):
            plainText = path
        }

        pasteboard.setString(plainText, forType: .string)

        // Update change count to ignore this clipboard change
        lastChangeCount = NSPasteboard.general.changeCount

        // Close popover and paste to previous app
        AppDelegate.shared?.closePopoverAndPaste()
    }

    func delete(item: ClipboardItem) {
        let targetId = item.originalId
        items.removeAll { $0.originalId == targetId }
        contentCache[targetId] = nil
        contentCacheOrder.removeAll { $0 == targetId }
        store.deleteItem(id: targetId)
    }

    func toggleFavorite(item: ClipboardItem) {
        let targetId = item.originalId
        let newValue = !item.isFavorite

        for index in items.indices where items[index].originalId == targetId {
            items[index].isFavorite = newValue
        }
        if var cached = contentCache[targetId] {
            cached.isFavorite = newValue
            contentCache[targetId] = cached
        }
        store.setFavorite(itemId: targetId, isFavorite: newValue)
    }

    func togglePin(item: ClipboardItem) {
        let targetId = item.originalId
        let newValue = !item.isDirectPinned

        for index in items.indices where items[index].originalId == targetId {
            items[index].isDirectPinned = newValue
            items[index].pinType = newValue ? .direct : .none
        }
        if var cached = contentCache[targetId] {
            cached.isDirectPinned = newValue
            cached.pinType = newValue ? .direct : .none
            contentCache[targetId] = cached
        }
        store.setPinned(itemId: targetId, isPinned: newValue)
    }

    func setAlias(itemId: UUID, alias: String?) {
        for index in items.indices where items[index].originalId == itemId {
            items[index].alias = alias
        }
        if var cached = contentCache[itemId] {
            cached.alias = alias
            contentCache[itemId] = cached
        }
        store.setAlias(itemId: itemId, alias: alias)
    }

    func fullItem(for item: ClipboardItem) -> ClipboardItem? {
        if item.isContentLoaded {
            cacheFullItem(item)
            return item
        }

        let targetId = item.originalId
        if let cached = contentCache[targetId] {
            return applyingRuntimeMetadata(from: item, to: cached)
        }

        guard let loaded = store.loadItem(id: targetId) else {
            return nil
        }

        cacheFullItem(loaded)
        return applyingRuntimeMetadata(from: item, to: loaded)
    }

    func cachedFullItem(for item: ClipboardItem) -> ClipboardItem? {
        guard let cached = contentCache[item.originalId] else { return nil }
        return applyingRuntimeMetadata(from: item, to: cached)
    }

    func prefetchContent(around index: Int, in sourceItems: [ClipboardItem]? = nil, radius: Int = 3) {
        let snapshot = sourceItems ?? items
        guard !snapshot.isEmpty else { return }

        let lowerBound = max(0, index - radius)
        let upperBound = min(snapshot.count - 1, index + radius)
        let idsToLoad = snapshot[lowerBound...upperBound]
            .filter { !$0.isContentLoaded && contentCache[$0.originalId] == nil }
            .map(\.originalId)

        guard !idsToLoad.isEmpty else { return }

        Task.detached { [weak self] in
            guard let self = self else { return }

            for itemId in idsToLoad {
                guard let loaded = self.store.loadItem(id: itemId) else { continue }
                await MainActor.run {
                    self.cacheFullItem(loaded)
                }
            }
        }
    }

    private func cacheFullItem(_ item: ClipboardItem) {
        let targetId = item.originalId
        var fullItem = item
        fullItem.virtualId = nil
        fullItem.pinType = item.isDirectPinned ? .direct : .none
        fullItem.isContentLoaded = true

        contentCache[targetId] = fullItem
        contentCacheOrder.removeAll { $0 == targetId }
        contentCacheOrder.append(targetId)

        while contentCacheOrder.count > maxContentCacheCount {
            let idToRemove = contentCacheOrder.removeFirst()
            contentCache[idToRemove] = nil
        }

        for index in items.indices where items[index].originalId == targetId && !items[index].isContentLoaded {
            items[index] = applyingRuntimeMetadata(from: items[index], to: fullItem)
        }

        objectWillChange.send()
    }

    private func applyingRuntimeMetadata(from source: ClipboardItem, to fullItem: ClipboardItem) -> ClipboardItem {
        var item = fullItem
        item.virtualId = source.virtualId
        item.pinType = source.pinType
        item.isDirectPinned = source.isDirectPinned
        item.isFavorite = source.isFavorite
        item.alias = source.alias
        item.previewText = source.previewText ?? fullItem.previewText
        item.isExternallyStored = source.isExternallyStored
        item.isContentLoaded = true
        return item
    }

    func clearHistory() {
        // Clear all items from database
        store.clearAllItems()

        // Clear in-memory items
        items = []
        contentCache.removeAll()
        contentCacheOrder.removeAll()
        currentQuery = nil
        currentTagIds = []
        currentOffset = 0
        hasMore = false
    }

    // MARK: - Unified Pagination with Optional Search

    /// Current search query (nil = browse all)
    private(set) var currentQuery: String? = nil

    /// Current tag IDs filter (empty = no filter)
    private(set) var currentTagIds: [String] = []

    /// Current content type filter (nil = all types)
    private(set) var currentContentType: String? = nil

    /// Current regex mode
    private(set) var currentIsRegex: Bool = false

    /// Current page offset (for tracking position in database)
    private(set) var currentOffset: Int = 0

    /// Whether there are more items to load
    @Published private(set) var hasMore: Bool = true

    /// Set search query and/or tag filter, then reload items
    /// Runs database query on a background thread to avoid blocking UI
    func setSearchQuery(_ query: String?, tagIds: [String]? = nil, contentType: String? = nil, isRegex: Bool = false) {
        activeFilter = nil
        let trimmedQuery = query?.trimmingCharacters(in: .whitespaces)
        currentQuery = (trimmedQuery?.isEmpty ?? true) ? nil : trimmedQuery
        currentTagIds = tagIds ?? []
        currentContentType = contentType
        currentIsRegex = isRegex
        currentOffset = 0
        hasMore = true  // Reset

        // Capture values for background task
        let capturedQuery = currentQuery
        let capturedTagIds = currentTagIds
        let capturedContentType = currentContentType
        let capturedIsRegex = currentIsRegex

        Task.detached { [weak self] in
            guard let self = self else { return }
            let loadedItems = self.store.loadItems(
                limit: 100, offset: 0,
                query: capturedQuery,
                tagIds: capturedTagIds.isEmpty ? nil : capturedTagIds,
                contentType: capturedContentType,
                isRegex: capturedIsRegex
            )

            await MainActor.run {
                // Only update if the query hasn't changed while we were loading
                guard self.currentQuery == capturedQuery,
                      self.currentTagIds == capturedTagIds,
                      self.currentContentType == capturedContentType,
                      self.currentIsRegex == capturedIsRegex else { return }

                self.items = loadedItems
                self.prefetchContent(around: 0)
                if loadedItems.count < 100 {
                    self.hasMore = false
                }
            }
        }
    }

    /// Set advanced filter and reload items
    func setAdvancedFilter(_ filter: FilterQuery?) {
        activeFilter = filter
        currentOffset = 0
        hasMore = true

        if let filter = filter, filter.isActive {
            let loadedItems = store.loadFilteredItems(filter: filter, limit: 100, offset: 0)
            items = loadedItems
            prefetchContent(around: 0)

            if loadedItems.count < 100 {
                hasMore = false
            }
        } else {
            // No filter or empty filter - load all items
            activeFilter = nil
            let loadedItems = store.loadItems(limit: 100, offset: 0)
            items = loadedItems
            prefetchContent(around: 0)

            if loadedItems.count < 100 {
                hasMore = false
            }
        }
    }

    /// Get distinct source apps for filter dropdown
    func getDistinctSourceApps() -> [String] {
        store.getDistinctSourceApps()
    }

    private var isFiltering: Bool {
        if activeFilter?.isActive == true { return true }
        return currentQuery != nil || !currentTagIds.isEmpty || currentContentType != nil || currentIsRegex
    }

    private func loadPage(limit: Int, offset: Int) -> [ClipboardItem] {
        if let activeFilter, activeFilter.isActive {
            return store.loadFilteredItems(filter: activeFilter, limit: limit, offset: offset)
        }

        return store.loadItems(
            limit: limit,
            offset: offset,
            query: currentQuery,
            tagIds: currentTagIds.isEmpty ? nil : currentTagIds,
            contentType: currentContentType,
            isRegex: currentIsRegex
        )
    }

    private func loadNextPage(after item: ClipboardItem?, limit: Int) -> [ClipboardItem] {
        guard let beforePosition = item?.position else {
            return loadPage(limit: limit, offset: 0)
        }

        if let activeFilter, activeFilter.isActive {
            return store.loadFilteredItemsBeforePosition(
                filter: activeFilter,
                limit: limit,
                beforePosition: beforePosition
            )
        }

        return store.loadItemsBeforePosition(
            limit: limit,
            beforePosition: beforePosition,
            query: currentQuery,
            tagIds: currentTagIds.isEmpty ? nil : currentTagIds,
            contentType: currentContentType,
            isRegex: currentIsRegex
        )
    }

    /// Load more items (next page)
    func loadMore() {
        // Skip if no more items
        guard hasMore else { return }

        let moreItems = loadNextPage(after: items.last, limit: 100)

        // If got less than page size, no more items
        if moreItems.count < 100 {
            hasMore = false
        }

        // Filter out duplicates
        let existingIds = Set(items.map { $0.id })
        let newItems = moreItems.filter { !existingIds.contains($0.id) }

        if !newItems.isEmpty {
            items.append(contentsOf: newItems)
            prefetchContent(around: max(0, items.count - newItems.count))
        } else {
            // No new items, definitely no more
            hasMore = false
        }
    }

    /// Load the last page of items (for wrap-around from first to last)
    /// Returns the index of the last item
    func loadLastPage() -> Int {
        let pageSize = 100
        let total = isFiltering ? max(items.count + pageSize, 1) : itemCount
        if total == 0 { return 0 }

        // For search, we need to get total count first (expensive for LIKE)
        // For now, just load from a high offset and adjust
        if isFiltering {
            // For search results, try to load "last" by getting more results
            let lastPageItems = loadPage(limit: pageSize, offset: max(0, items.count))
            if !lastPageItems.isEmpty {
                items.append(contentsOf: lastPageItems)
            }
            return max(0, items.count - 1)
        }

        // For normal browsing
        let lastPageOffset = max(0, total - pageSize)
        items = loadPage(limit: pageSize, offset: lastPageOffset)
        currentOffset = lastPageOffset
        prefetchContent(around: max(0, items.count - 1))

        return items.count - 1
    }

    /// Load the first page of items (for wrap-around from last to first)
    func loadFirstPage() {
        currentOffset = 0
        items = loadPage(limit: 100, offset: 0)
        hasMore = items.count >= 100
        prefetchContent(around: 0)
    }

    /// Load previous page (for navigating up)
    /// Returns true if there was a previous page to load
    func loadPreviousPage() -> Bool {
        if currentOffset <= 0 { return false }

        let pageSize = 100
        let newOffset = max(0, currentOffset - pageSize)

        let prevItems = loadPage(limit: pageSize, offset: newOffset)

        // Prepend previous page items
        items = prevItems + items
        currentOffset = newOffset
        prefetchContent(around: 0)

        return true
    }

    /// Load items up to and including a specific item by ID
    /// Returns the index of the item in the loaded list, or nil if not found
    func loadToItem(itemId: UUID) -> Int? {
        // Get the item's offset in the database
        guard let itemOffset = store.getItemRankOffset(itemId: itemId.uuidString) else {
            return nil
        }

        // Calculate how many items we need to load
        let pageSize = 100
        // Load enough pages to include the item, plus some buffer
        let neededItems = itemOffset + pageSize

        // Reload from start with enough items
        currentOffset = 0
        items = store.loadItems(limit: neededItems, offset: 0, query: nil)
        hasMore = items.count >= neededItems

        // Find the item's index in the loaded list
        return items.firstIndex(where: { $0.id == itemId })
    }

    // MARK: - Persistence

    private func loadData() {
        items = store.loadItems(limit: 100, offset: 0)
        favoriteGroups = store.loadGroups()
        // Use MAX position from database to prevent unique constraint errors
        positionCounter = store.maxPosition()
        prefetchContent(around: 0)
    }

    func reloadFromDatabase() {
        items = store.loadItems(limit: 100, offset: 0)
        prefetchContent(around: 0)
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

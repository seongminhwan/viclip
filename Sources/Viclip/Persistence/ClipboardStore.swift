import Foundation

class ClipboardStore {
    private let fileManager = FileManager.default
    private let databaseManager = DatabaseManager.shared
    private let largeFileStorage = LargeFileStorage.shared
    private let storageSettings = StorageSettings.shared
    
    private var storageURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vtoolDir = appSupport.appendingPathComponent("VTool", isDirectory: true)
        
        if !fileManager.fileExists(atPath: vtoolDir.path) {
            try? fileManager.createDirectory(at: vtoolDir, withIntermediateDirectories: true)
        }
        
        return vtoolDir
    }
    
    private var legacyItemsURL: URL {
        storageURL.appendingPathComponent("items.json")
    }
    
    private var legacyGroupsURL: URL {
        storageURL.appendingPathComponent("groups.json")
    }
    
    // MARK: - Initialization
    
    init() {
        migrateFromLegacyIfNeeded()
    }
    
    // MARK: - Items
    
    /// Unified interface for loading items with optional search and tag filter
    func loadItems(limit: Int = 100, offset: Int = 0, query: String? = nil, tagIds: [String]? = nil) -> [ClipboardItem] {
        do {
            let dbItems = try databaseManager.fetchItems(limit: limit, offset: offset, query: query, tagIds: tagIds)
            return dbItems.compactMap { dbItem -> ClipboardItem? in
                var item = dbItem.toClipboardItem()
                
                // Load content from external storage if needed
                if dbItem.isExternal, let data = largeFileStorage.retrieve(for: dbItem.id) {
                    item?.content = contentFromData(data, type: dbItem.contentType)
                    item?.isExternallyStored = true
                }
                
                return item
            }
        } catch {
            print("Error loading items: \(error)")
            return []
        }
    }
    
    func loadAllItems() -> [ClipboardItem] {
        do {
            let count = try databaseManager.itemCount()
            return loadItems(limit: count, offset: 0)
        } catch {
            return []
        }
    }
    
    func saveItem(_ item: ClipboardItem) {
        do {
            var dbItem = DBClipboardItem(from: item)
            
            // Check if should store externally
            if storageSettings.enableExternalStorage && item.contentSize > storageSettings.largeFileThreshold {
                if let data = contentToData(item.content) {
                    try largeFileStorage.store(content: data, for: item.id.uuidString)
                    dbItem.isExternal = true
                    dbItem.content = nil  // Don't store in DB
                }
            }
            
            try databaseManager.insertItem(dbItem)
        } catch {
            print("Error saving item: \(error)")
        }
    }
    
    func updateItem(_ item: ClipboardItem) {
        do {
            var dbItem = DBClipboardItem(from: item)
            
            if item.isExternallyStored {
                dbItem.isExternal = true
                dbItem.content = nil
            }
            
            try databaseManager.updateItem(dbItem)
        } catch {
            print("Error updating item: \(error)")
        }
    }
    
    func deleteItem(id: UUID) {
        do {
            try databaseManager.deleteItem(id: id.uuidString)
            largeFileStorage.delete(for: id.uuidString)
        } catch {
            print("Error deleting item: \(error)")
        }
    }
    
    /// Clear all items from database and rebuild FTS index
    func clearAllItems() {
        do {
            try databaseManager.deleteAllItems()
            // Also clear all external storage files
            largeFileStorage.deleteAllExternalFiles()
        } catch {
            print("Error clearing all items: \(error)")
        }
    }
    
    func searchItems(query: String) -> [ClipboardItem] {
        do {
            let dbItems = try databaseManager.searchItems(query: query)
            return dbItems.compactMap { dbItem -> ClipboardItem? in
                var item = dbItem.toClipboardItem()
                
                if dbItem.isExternal, let data = largeFileStorage.retrieve(for: dbItem.id) {
                    item?.content = contentFromData(data, type: dbItem.contentType)
                    item?.isExternallyStored = true
                }
                
                return item
            }
        } catch {
            print("Error searching items: \(error)")
            return []
        }
    }
    
    /// Load items with advanced filter
    func loadFilteredItems(filter: FilterQuery, limit: Int = 100, offset: Int = 0) -> [ClipboardItem] {
        do {
            let dbItems = try databaseManager.fetchFilteredItems(filter: filter, limit: limit, offset: offset)
            return dbItems.compactMap { dbItem -> ClipboardItem? in
                var item = dbItem.toClipboardItem()
                
                if dbItem.isExternal, let data = largeFileStorage.retrieve(for: dbItem.id) {
                    item?.content = contentFromData(data, type: dbItem.contentType)
                    item?.isExternallyStored = true
                }
                
                return item
            }
        } catch {
            print("Error loading filtered items: \(error)")
            return []
        }
    }
    
    /// Get distinct source apps for filter dropdown
    func getDistinctSourceApps() -> [String] {
        do {
            return try databaseManager.fetchDistinctSourceApps()
        } catch {
            print("Error fetching source apps: \(error)")
            return []
        }
    }
    
    // MARK: - Groups
    
    func loadGroups() -> [FavoriteGroup] {
        // TODO: Implement with database
        return []
    }
    
    func saveGroups(_ groups: [FavoriteGroup]) {
        // TODO: Implement with database
    }
    
    // MARK: - Statistics
    
    func itemCount() -> Int {
        (try? databaseManager.itemCount()) ?? 0
    }
    
    func maxPosition() -> Int {
        (try? databaseManager.maxPosition()) ?? 0
    }
    
    func totalSize() -> Int64 {
        let dbSize = (try? databaseManager.totalContentSize()) ?? 0
        let externalSize = largeFileStorage.totalExternalSize()
        return dbSize + externalSize
    }
    
    func externalFileCount() -> Int {
        largeFileStorage.externalFileCount()
    }
    
    /// Get the offset (0-based index) of an item in the sorted list
    func getItemRankOffset(itemId: String) -> Int? {
        try? databaseManager.getItemRankOffset(itemId: itemId)
    }
    
    // MARK: - Migration
    
    private func migrateFromLegacyIfNeeded() {
        guard fileManager.fileExists(atPath: legacyItemsURL.path) else { return }
        
        // Skip if database already has items (already migrated)
        if (try? databaseManager.itemCount()) ?? 0 > 0 {
            // Remove legacy file since we already have data
            try? fileManager.removeItem(at: legacyItemsURL)
            print("Migration skipped: database already has data")
            return
        }
        
        do {
            // Load legacy items
            let data = try Data(contentsOf: legacyItemsURL)
            let decoder = JSONDecoder()
            let legacyItems = try decoder.decode([ClipboardItem].self, from: data)
            
            // Migrate to database
            try databaseManager.migrateFromJSON(items: legacyItems)
            
            // Remove legacy file after successful migration
            try? fileManager.removeItem(at: legacyItemsURL)
            
            print("Migrated \(legacyItems.count) items from JSON to SQLite")
        } catch {
            print("Migration error: \(error)")
            // Keep the legacy file for debugging
        }
    }
    
    func migrateExternalToDatabase() -> Int {
        var migratedCount = 0
        
        do {
            let externalItems = try databaseManager.getExternalItems()
            
            for dbItem in externalItems {
                guard let data = largeFileStorage.migrateToDatabase(itemId: dbItem.id) else { continue }
                
                var updatedItem = dbItem
                updatedItem.content = data
                updatedItem.isExternal = false
                
                try databaseManager.updateItem(updatedItem)
                migratedCount += 1
            }
        } catch {
            print("Migration to database error: \(error)")
        }
        
        return migratedCount
    }
    
    func migrateLargeToExternal() -> Int {
        var migratedCount = 0
        
        do {
            let largeItems = try databaseManager.getLargeItems(thresholdBytes: storageSettings.largeFileThreshold)
            
            for dbItem in largeItems {
                guard let content = dbItem.content else { continue }
                
                try largeFileStorage.store(content: content, for: dbItem.id)
                
                var updatedItem = dbItem
                updatedItem.content = nil
                updatedItem.isExternal = true
                
                try databaseManager.updateItem(updatedItem)
                migratedCount += 1
            }
        } catch {
            print("Migration to external error: \(error)")
        }
        
        return migratedCount
    }
    
    // MARK: - Retention Cleanup
    
    /// Delete items older than the specified number of days
    /// Returns the number of deleted items
    @discardableResult
    func deleteExpiredItems(olderThanDays days: Int) -> Int {
        guard days > 0 else { return 0 }
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        do {
            // Get items to delete (excluding favorites)
            let expiredItems = try databaseManager.fetchItemsOlderThan(date: cutoffDate)
            var deletedCount = 0
            
            for item in expiredItems {
                // Skip favorites
                if item.isFavorite { continue }
                
                try databaseManager.deleteItem(id: item.id)
                largeFileStorage.delete(for: item.id)
                deletedCount += 1
            }
            
            if deletedCount > 0 {
                print("[Retention] Deleted \(deletedCount) items older than \(days) days")
            }
            return deletedCount
        } catch {
            print("[Retention] Error deleting expired items: \(error)")
            return 0
        }
    }
    
    /// Enforce maximum item count by deleting oldest non-favorite items
    /// Returns the number of deleted items
    @discardableResult
    func enforceItemLimit(maxItems: Int) -> Int {
        guard maxItems > 0 else { return 0 }
        
        do {
            let currentCount = try databaseManager.itemCount()
            guard currentCount > maxItems else { return 0 }
            
            let excessCount = currentCount - maxItems
            let oldestItems = try databaseManager.fetchOldestItems(limit: excessCount + 100) // Get extra to skip favorites
            
            var deletedCount = 0
            for item in oldestItems {
                if deletedCount >= excessCount { break }
                
                // Skip favorites
                if item.isFavorite { continue }
                
                try databaseManager.deleteItem(id: item.id)
                largeFileStorage.delete(for: item.id)
                deletedCount += 1
            }
            
            if deletedCount > 0 {
                print("[Retention] Deleted \(deletedCount) items to enforce limit of \(maxItems)")
            }
            return deletedCount
        } catch {
            print("[Retention] Error enforcing item limit: \(error)")
            return 0
        }
    }
    
    /// Run all enabled retention policies
    func runRetentionCleanup() {
        let maxItemsEnabled = UserDefaults.standard.bool(forKey: "retentionMaxItemsEnabled")
        let maxItems = UserDefaults.standard.integer(forKey: "retentionMaxItems")
        let maxAgeEnabled = UserDefaults.standard.bool(forKey: "retentionMaxAgeEnabled")
        let maxAgeDays = UserDefaults.standard.integer(forKey: "retentionMaxAgeDays")
        
        if maxAgeEnabled && maxAgeDays > 0 {
            deleteExpiredItems(olderThanDays: maxAgeDays)
        }
        
        if maxItemsEnabled && maxItems > 0 {
            enforceItemLimit(maxItems: maxItems)
        }
    }
    
    func clearAll() {
        try? databaseManager.clearAll()
        largeFileStorage.deleteAllExternalFiles()
    }
    
    // MARK: - Helpers
    
    private func contentToData(_ content: ClipboardContent) -> Data? {
        switch content {
        case .text(let string):
            return string.data(using: .utf8)
        case .richText(let data):
            return data
        case .image(let data):
            return data
        case .fileURL(let path):
            return path.data(using: .utf8)
        }
    }
    
    private func contentFromData(_ data: Data, type: String) -> ClipboardContent {
        switch type {
        case "text":
            return .text(String(data: data, encoding: .utf8) ?? "")
        case "richText":
            return .richText(data)
        case "image":
            return .image(data)
        case "fileURL":
            return .fileURL(String(data: data, encoding: .utf8) ?? "")
        default:
            return .text("")
        }
    }
}

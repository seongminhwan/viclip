import Foundation
import GRDB

// MARK: - Database Manager
class DatabaseManager {
    static let shared = DatabaseManager()
    
    private var dbQueue: DatabaseQueue?
    private let fileManager = FileManager.default
    
    private var databaseURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vtoolDir = appSupport.appendingPathComponent("VTool", isDirectory: true)
        
        if !fileManager.fileExists(atPath: vtoolDir.path) {
            try? fileManager.createDirectory(at: vtoolDir, withIntermediateDirectories: true)
        }
        
        return vtoolDir.appendingPathComponent("vtool.db")
    }
    
    private init() {
        setupDatabase()
    }
    
    // MARK: - Setup
    
    private func setupDatabase() {
        do {
            var config = Configuration()
            config.prepareDatabase { db in
                // Enable foreign keys
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
            
            dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: config)
            try createTables()
        } catch {
            print("Database setup error: \(error)")
        }
    }
    
    private func createTables() throws {
        try dbQueue?.write { db in
            // Main items table - check if exists for migration
            let itemsTableExists = try db.tableExists("clipboard_items")
            if !itemsTableExists {
                try db.create(table: "clipboard_items") { t in
                    t.column("id", .text).primaryKey()
                    t.column("content_type", .text).notNull()
                    t.column("content", .blob)  // Can be NULL if externally stored
                    t.column("is_external", .boolean).defaults(to: false)
                    t.column("content_size", .integer).defaults(to: 0)
                    t.column("source_app", .text)
                    t.column("source_bundle_id", .text)
                    t.column("is_favorite", .boolean).defaults(to: false)
                    t.column("is_pinned", .boolean).defaults(to: false)
                    t.column("position", .integer).unique()
                    t.column("created_at", .double).notNull()
                }
            } else {
                // Migration: add is_pinned if not exists
                let columns = try db.columns(in: "clipboard_items")
                if !columns.contains(where: { $0.name == "is_pinned" }) {
                    try db.execute(sql: "ALTER TABLE clipboard_items ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0")
                }
            }
            
            // Create indexes
            try db.create(index: "idx_created_at", on: "clipboard_items", columns: ["created_at"], ifNotExists: true)
            try db.create(index: "idx_is_favorite", on: "clipboard_items", columns: ["is_favorite"], ifNotExists: true)
            try db.create(index: "idx_position", on: "clipboard_items", columns: ["position"], ifNotExists: true)
            try db.create(index: "idx_is_pinned", on: "clipboard_items", columns: ["is_pinned"], ifNotExists: true)
            
            // FTS5 full-text search table - recreate if corrupted
            do {
                // Check if FTS table works
                _ = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_fts")
            } catch {
                // Drop and recreate FTS table
                try? db.execute(sql: "DROP TABLE IF EXISTS clipboard_fts")
                try db.execute(sql: """
                    CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_fts USING fts5(
                        text_content,
                        content='clipboard_items',
                        content_rowid='rowid',
                        tokenize='unicode61'
                    )
                """)
            }
            
            // Favorite groups table
            try db.create(table: "favorite_groups", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("icon", .text)
                t.column("item_ids", .text)  // JSON array of item IDs
                t.column("created_at", .double).notNull()
            }
            
            // Tags table - create fresh or migrate
            let tagsTableExists = try db.tableExists("tags")
            if !tagsTableExists {
                try db.create(table: "tags") { t in
                    t.column("id", .text).primaryKey()
                    t.column("name", .text).notNull().unique()
                    t.column("color", .text)  // Optional hex color
                    t.column("position", .integer).notNull().defaults(to: 0)
                    t.column("is_pinned", .boolean).notNull().defaults(to: false)
                    t.column("created_at", .double).notNull()
                }
            } else {
                // Check if position column exists, add if not
                let columns = try db.columns(in: "tags")
                if !columns.contains(where: { $0.name == "position" }) {
                    try db.execute(sql: "ALTER TABLE tags ADD COLUMN position INTEGER NOT NULL DEFAULT 0")
                }
                // Check if is_pinned column exists, add if not
                if !columns.contains(where: { $0.name == "is_pinned" }) {
                    try db.execute(sql: "ALTER TABLE tags ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0")
                }
            }
            
            // Create index for tag name (safe to run even if exists)
            try db.create(index: "idx_tags_name", on: "tags", columns: ["name"], ifNotExists: true)
            try db.create(index: "idx_tags_position", on: "tags", columns: ["position"], ifNotExists: true)
            
            // Clipboard item to tag junction table (many-to-many)
            try db.create(table: "clipboard_item_tags", ifNotExists: true) { t in
                t.column("item_id", .text).notNull()
                t.column("tag_id", .text).notNull()
                t.column("created_at", .double).notNull()
                t.primaryKey(["item_id", "tag_id"])
                t.foreignKey(["item_id"], references: "clipboard_items", columns: ["id"], onDelete: .cascade)
                t.foreignKey(["tag_id"], references: "tags", columns: ["id"], onDelete: .cascade)
            }
            
            // Create indexes for junction table
            try db.create(index: "idx_item_tags_item", on: "clipboard_item_tags", columns: ["item_id"], ifNotExists: true)
            try db.create(index: "idx_item_tags_tag", on: "clipboard_item_tags", columns: ["tag_id"], ifNotExists: true)
        }
    }
    
    // MARK: - CRUD Operations
    
    func insertItem(_ item: DBClipboardItem) throws {
        try dbQueue?.write { db in
            try item.insert(db)
            
            // Update FTS index for text content
            if let textContent = item.textContent {
                try db.execute(
                    sql: "INSERT INTO clipboard_fts(rowid, text_content) SELECT rowid, ? FROM clipboard_items WHERE id = ?",
                    arguments: [textContent, item.id]
                )
            }
        }
    }
    
    func updateItem(_ item: DBClipboardItem) throws {
        try dbQueue?.write { db in
            try item.update(db)
            
            // Update FTS index (may fail if FTS table is corrupted - ignore)
            if let textContent = item.textContent {
                do {
                    try db.execute(
                        sql: "DELETE FROM clipboard_fts WHERE rowid = (SELECT rowid FROM clipboard_items WHERE id = ?)",
                        arguments: [item.id]
                    )
                    try db.execute(
                        sql: "INSERT INTO clipboard_fts(rowid, text_content) SELECT rowid, ? FROM clipboard_items WHERE id = ?",
                        arguments: [textContent, item.id]
                    )
                } catch {
                    // FTS table may be corrupted, ignore and continue
                    print("Warning: Could not update FTS index: \(error)")
                }
            }
        }
    }
    
    func deleteItem(id: String) throws {
        try dbQueue?.write { db in
            // Delete from FTS first (may fail if FTS table is corrupted - ignore)
            do {
                try db.execute(
                    sql: "DELETE FROM clipboard_fts WHERE rowid = (SELECT rowid FROM clipboard_items WHERE id = ?)",
                    arguments: [id]
                )
            } catch {
                // FTS table may be corrupted, ignore and continue
                print("Warning: Could not delete from FTS index: \(error)")
            }
            // Delete from main table
            try db.execute(sql: "DELETE FROM clipboard_items WHERE id = ?", arguments: [id])
        }
    }
    
    /// Get the maximum position value in the database
    func maxPosition() throws -> Int {
        try dbQueue?.read { db in
            try Int.fetchOne(db, sql: "SELECT MAX(position) FROM clipboard_items") ?? 0
        } ?? 0
    }
    
    /// Unified interface for fetching items with optional search
    /// - Parameters:
    ///   - limit: Max items to return
    ///   - offset: Offset for pagination
    ///   - query: Optional search query (nil = browse all, non-nil = search)
    ///   - tagIds: Optional tag IDs to filter by (nil = no filter, empty = no filter, non-empty = items must have ANY of these tags)
    func fetchItems(limit: Int = 100, offset: Int = 0, query: String? = nil, tagIds: [String]? = nil) throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            // Build tag filter subquery if needed
            let hasTagFilter = !(tagIds?.isEmpty ?? true)
            
            // If no query and no tags, return all items with pagination
            guard let searchQuery = query, !searchQuery.isEmpty else {
                if hasTagFilter {
                    // Filter by tags using subquery
                    let placeholders = tagIds!.map { _ in "?" }.joined(separator: ", ")
                    let sql = """
                        SELECT DISTINCT clipboard_items.* FROM clipboard_items
                        INNER JOIN clipboard_item_tags ON clipboard_items.id = clipboard_item_tags.item_id
                        WHERE clipboard_item_tags.tag_id IN (\(placeholders))
                        ORDER BY clipboard_items.position DESC
                        LIMIT ? OFFSET ?
                    """
                    var args: [any DatabaseValueConvertible] = tagIds!
                    args.append(limit)
                    args.append(offset)
                    return try DBClipboardItem.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                } else {
                    return try DBClipboardItem
                        .order(Column("position").desc)
                        .limit(limit, offset: offset)
                        .fetchAll(db)
                }
            }
            
            // Check if query contains FTS5 special characters
            let specialChars = CharacterSet(charactersIn: "#\"*:^()[]{}~-")
            let hasSpecialChars = searchQuery.unicodeScalars.contains { specialChars.contains($0) }
            
            if hasSpecialChars {
                // Use LIKE for queries with special characters
                if hasTagFilter {
                    let placeholders = tagIds!.map { _ in "?" }.joined(separator: ", ")
                    let sql = """
                        SELECT DISTINCT clipboard_items.* FROM clipboard_items
                        INNER JOIN clipboard_item_tags ON clipboard_items.id = clipboard_item_tags.item_id
                        WHERE clipboard_items.content LIKE ?
                        AND clipboard_item_tags.tag_id IN (\(placeholders))
                        ORDER BY clipboard_items.position DESC
                        LIMIT ? OFFSET ?
                    """
                    var args: [any DatabaseValueConvertible] = ["%\(searchQuery)%"]
                    args.append(contentsOf: tagIds!)
                    args.append(limit)
                    args.append(offset)
                    return try DBClipboardItem.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                } else {
                    let sql = """
                        SELECT * FROM clipboard_items
                        WHERE content LIKE ?
                        ORDER BY position DESC
                        LIMIT ? OFFSET ?
                    """
                    return try DBClipboardItem.fetchAll(db, sql: sql, arguments: ["%\(searchQuery)%", limit, offset])
                }
            } else {
                // Use FTS5 for normal queries (faster), with fallback to LIKE if FTS fails
                do {
                    if hasTagFilter {
                        let placeholders = tagIds!.map { _ in "?" }.joined(separator: ", ")
                        let sql = """
                            SELECT DISTINCT clipboard_items.* FROM clipboard_items
                            JOIN clipboard_fts ON clipboard_items.rowid = clipboard_fts.rowid
                            INNER JOIN clipboard_item_tags ON clipboard_items.id = clipboard_item_tags.item_id
                            WHERE clipboard_fts MATCH ?
                            AND clipboard_item_tags.tag_id IN (\(placeholders))
                            ORDER BY clipboard_items.position DESC
                            LIMIT ? OFFSET ?
                        """
                        let safeQuery = searchQuery.trimmingCharacters(in: .whitespaces)
                        var args: [any DatabaseValueConvertible] = ["\"\(safeQuery)\"*"]
                        args.append(contentsOf: tagIds!)
                        args.append(limit)
                        args.append(offset)
                        return try DBClipboardItem.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                    } else {
                        let sql = """
                            SELECT clipboard_items.* FROM clipboard_items
                            JOIN clipboard_fts ON clipboard_items.rowid = clipboard_fts.rowid
                            WHERE clipboard_fts MATCH ?
                            ORDER BY clipboard_items.position DESC
                            LIMIT ? OFFSET ?
                        """
                        let safeQuery = searchQuery.trimmingCharacters(in: .whitespaces)
                        return try DBClipboardItem.fetchAll(db, sql: sql, arguments: ["\"\(safeQuery)\"*", limit, offset])
                    }
                } catch {
                    // FTS failed (table corrupted), fallback to LIKE search
                    print("FTS search failed, falling back to LIKE: \(error)")
                    if hasTagFilter {
                        let placeholders = tagIds!.map { _ in "?" }.joined(separator: ", ")
                        let sql = """
                            SELECT DISTINCT clipboard_items.* FROM clipboard_items
                            INNER JOIN clipboard_item_tags ON clipboard_items.id = clipboard_item_tags.item_id
                            WHERE clipboard_items.content LIKE ?
                            AND clipboard_item_tags.tag_id IN (\(placeholders))
                            ORDER BY clipboard_items.position DESC
                            LIMIT ? OFFSET ?
                        """
                        var args: [any DatabaseValueConvertible] = ["%\(searchQuery)%"]
                        args.append(contentsOf: tagIds!)
                        args.append(limit)
                        args.append(offset)
                        return try DBClipboardItem.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                    } else {
                        let sql = """
                            SELECT * FROM clipboard_items
                            WHERE content LIKE ?
                            ORDER BY position DESC
                            LIMIT ? OFFSET ?
                        """
                        return try DBClipboardItem.fetchAll(db, sql: sql, arguments: ["%\(searchQuery)%", limit, offset])
                    }
                }
            }
        } ?? []
    }
    
    func fetchFavorites() throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            try DBClipboardItem
                .filter(Column("is_favorite") == true)
                .order(Column("position").desc)
                .fetchAll(db)
        } ?? []
    }
    
    func searchItems(query: String, limit: Int = 100) throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            // Check if query contains FTS5 special characters
            let specialChars = CharacterSet(charactersIn: "#\"*:^()[]{}~-")
            let hasSpecialChars = query.unicodeScalars.contains { specialChars.contains($0) }
            
            if hasSpecialChars {
                // Use LIKE for queries with special characters
                let sql = """
                    SELECT * FROM clipboard_items
                    WHERE content LIKE ?
                    ORDER BY position DESC
                    LIMIT ?
                """
                return try DBClipboardItem.fetchAll(db, sql: sql, arguments: ["%\(query)%", limit])
            } else {
                // Use FTS5 for normal queries (faster)
                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
                
                let sql = """
                    SELECT clipboard_items.* FROM clipboard_items
                    JOIN clipboard_fts ON clipboard_items.rowid = clipboard_fts.rowid
                    WHERE clipboard_fts MATCH ?
                    ORDER BY clipboard_items.position DESC
                    LIMIT ?
                """
                // Quote the query for phrase search and add prefix matching
                let safeQuery = query.trimmingCharacters(in: .whitespaces)
                return try DBClipboardItem.fetchAll(db, sql: sql, arguments: ["\"\(safeQuery)\"*", limit])
            }
        } ?? []
    }
    
    func itemCount() throws -> Int {
        try dbQueue?.read { db in
            try DBClipboardItem.fetchCount(db)
        } ?? 0
    }
    
    func totalContentSize() throws -> Int64 {
        try dbQueue?.read { db in
            try Int64.fetchOne(db, sql: "SELECT SUM(content_size) FROM clipboard_items") ?? 0
        } ?? 0
    }
    
    func getLargeItems(thresholdBytes: Int) throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            try DBClipboardItem
                .filter(Column("content_size") > thresholdBytes)
                .filter(Column("is_external") == false)
                .fetchAll(db)
        } ?? []
    }
    
    func getExternalItems() throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            try DBClipboardItem
                .filter(Column("is_external") == true)
                .fetchAll(db)
        } ?? []
    }
    
    // MARK: - Retention Queries
    
    /// Fetch items older than the specified date
    func fetchItemsOlderThan(date: Date) throws -> [DBClipboardItem] {
        let timestamp = date.timeIntervalSince1970
        return try dbQueue?.read { db in
            try DBClipboardItem
                .filter(Column("created_at") < timestamp)
                .order(Column("created_at").asc)
                .fetchAll(db)
        } ?? []
    }
    
    /// Fetch the oldest items (for enforcing item limit)
    func fetchOldestItems(limit: Int) throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            try DBClipboardItem
                .order(Column("created_at").asc)
                .limit(limit)
                .fetchAll(db)
        } ?? []
    }
    
    // MARK: - Migration
    
    func migrateFromJSON(items: [ClipboardItem]) throws {
        try dbQueue?.write { db in
            for item in items {
                let dbItem = DBClipboardItem(from: item)
                try dbItem.insert(db)
                
                // Add to FTS
                if let textContent = dbItem.textContent {
                    try db.execute(
                        sql: "INSERT INTO clipboard_fts(rowid, text_content) SELECT rowid, ? FROM clipboard_items WHERE id = ?",
                        arguments: [textContent, dbItem.id]
                    )
                }
            }
        }
    }
    
    func clearAll() throws {
        try dbQueue?.write { db in
            try db.execute(sql: "DELETE FROM clipboard_fts")
            try db.execute(sql: "DELETE FROM clipboard_items")
            try db.execute(sql: "DELETE FROM favorite_groups")
        }
    }
}

// MARK: - Database Model
struct DBClipboardItem: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboard_items"
    
    var id: String
    var contentType: String
    var content: Data?
    var isExternal: Bool
    var contentSize: Int
    var sourceApp: String?
    var sourceBundleId: String?
    var isFavorite: Bool
    var isPinned: Bool
    var position: Int
    var createdAt: Double
    
    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case content
        case isExternal = "is_external"
        case contentSize = "content_size"
        case sourceApp = "source_app"
        case sourceBundleId = "source_bundle_id"
        case isFavorite = "is_favorite"
        case isPinned = "is_pinned"
        case position
        case createdAt = "created_at"
    }
    
    // Helper to extract text for FTS
    var textContent: String? {
        guard contentType == "text" || contentType == "fileURL" else { return nil }
        guard let data = content else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // Convert from ClipboardItem
    init(from item: ClipboardItem) {
        self.id = item.id.uuidString
        self.position = item.position
        self.sourceApp = item.sourceApp
        self.sourceBundleId = item.sourceAppBundleId
        self.isFavorite = item.isFavorite
        self.isPinned = item.isDirectPinned
        self.createdAt = item.createdAt.timeIntervalSince1970
        self.isExternal = false
        
        switch item.content {
        case .text(let string):
            self.contentType = "text"
            self.content = string.data(using: .utf8)
            self.contentSize = self.content?.count ?? 0
        case .richText(let data):
            self.contentType = "richText"
            self.content = data
            self.contentSize = data.count
        case .image(let data):
            self.contentType = "image"
            self.content = data
            self.contentSize = data.count
        case .fileURL(let path):
            self.contentType = "fileURL"
            self.content = path.data(using: .utf8)
            self.contentSize = self.content?.count ?? 0
        }
    }
    
    // Convert to ClipboardItem
    func toClipboardItem() -> ClipboardItem? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        
        let clipboardContent: ClipboardContent
        switch contentType {
        case "text":
            guard let data = content, let text = String(data: data, encoding: .utf8) else { return nil }
            clipboardContent = .text(text)
        case "richText":
            guard let data = content else { return nil }
            clipboardContent = .richText(data)
        case "image":
            guard let data = content else { return nil }
            clipboardContent = .image(data)
        case "fileURL":
            guard let data = content, let path = String(data: data, encoding: .utf8) else { return nil }
            clipboardContent = .fileURL(path)
        default:
            return nil
        }
        
        return ClipboardItem(
            id: uuid,
            content: clipboardContent,
            sourceApp: sourceApp,
            sourceAppBundleId: sourceBundleId,
            createdAt: Date(timeIntervalSince1970: createdAt),
            position: position,
            isFavorite: isFavorite,
            isExternallyStored: isExternal,
            contentSize: contentSize,
            isDirectPinned: isPinned
        )
    }
}

// MARK: - Tag Database Model
struct DBTag: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tags"
    
    var id: String
    var name: String
    var color: String?
    var position: Int
    var isPinned: Bool
    var createdAt: Double
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case position
        case isPinned = "is_pinned"
        case createdAt = "created_at"
    }
    
    init(id: String = UUID().uuidString, name: String, color: String? = nil, position: Int = 0, isPinned: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.position = position
        self.isPinned = isPinned
        self.createdAt = Date().timeIntervalSince1970
    }
}

// MARK: - Clipboard Item Tag Junction Model
struct DBClipboardItemTag: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboard_item_tags"
    
    var itemId: String
    var tagId: String
    var createdAt: Double
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case tagId = "tag_id"
        case createdAt = "created_at"
    }
    
    init(itemId: String, tagId: String) {
        self.itemId = itemId
        self.tagId = tagId
        self.createdAt = Date().timeIntervalSince1970
    }
}

// MARK: - Tag Operations Extension
extension DatabaseManager {
    
    // MARK: - Tag CRUD
    
    func fetchAllTags() throws -> [DBTag] {
        try dbQueue?.read { db in
            try DBTag
                .order(Column("position").asc)
                .fetchAll(db)
        } ?? []
    }
    
    func insertTag(_ tag: DBTag) throws {
        try dbQueue?.write { db in
            var tagToInsert = tag
            // Set position to max + 1 if not specified
            if tagToInsert.position == 0 {
                let maxPosition = try Int.fetchOne(db, sql: "SELECT MAX(position) FROM tags") ?? 0
                tagToInsert.position = maxPosition + 1
            }
            try tagToInsert.insert(db)
        }
    }
    
    func updateTag(_ tag: DBTag) throws {
        try dbQueue?.write { db in
            try tag.update(db)
        }
    }
    
    func deleteTag(id: String) throws {
        try dbQueue?.write { db in
            try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [id])
        }
    }
    
    func tagExists(name: String) throws -> Bool {
        try dbQueue?.read { db in
            try DBTag.filter(Column("name") == name).fetchCount(db) > 0
        } ?? false
    }
    
    // MARK: - Item-Tag Relationship
    
    func addTagToItem(itemId: String, tagId: String) throws {
        try dbQueue?.write { db in
            let junction = DBClipboardItemTag(itemId: itemId, tagId: tagId)
            try junction.insert(db)
        }
    }
    
    func removeTagFromItem(itemId: String, tagId: String) throws {
        try dbQueue?.write { db in
            try db.execute(
                sql: "DELETE FROM clipboard_item_tags WHERE item_id = ? AND tag_id = ?",
                arguments: [itemId, tagId]
            )
        }
    }
    
    func fetchTagsForItem(itemId: String) throws -> [DBTag] {
        try dbQueue?.read { db in
            let sql = """
                SELECT t.* FROM tags t
                JOIN clipboard_item_tags cit ON t.id = cit.tag_id
                WHERE cit.item_id = ?
                ORDER BY t.position ASC
            """
            return try DBTag.fetchAll(db, sql: sql, arguments: [itemId])
        } ?? []
    }
    
    func fetchItemsWithTags(tagIds: [String]) throws -> [DBClipboardItem] {
        guard !tagIds.isEmpty else { return try fetchItems() }
        
        return try dbQueue?.read { db in
            let placeholders = tagIds.map { _ in "?" }.joined(separator: ", ")
            let sql = """
                SELECT DISTINCT ci.* FROM clipboard_items ci
                JOIN clipboard_item_tags cit ON ci.id = cit.item_id
                WHERE cit.tag_id IN (\(placeholders))
                ORDER BY ci.position DESC
            """
            return try DBClipboardItem.fetchAll(db, sql: sql, arguments: StatementArguments(tagIds))
        } ?? []
    }
    
    func setTagsForItem(itemId: String, tagIds: Set<String>) throws {
        try dbQueue?.write { db in
            // Remove all existing tags for this item
            try db.execute(sql: "DELETE FROM clipboard_item_tags WHERE item_id = ?", arguments: [itemId])
            
            // Add new tags
            for tagId in tagIds {
                let junction = DBClipboardItemTag(itemId: itemId, tagId: tagId)
                try junction.insert(db)
            }
        }
    }
    
    /// Pin type for items
    enum PinType: Int {
        case direct = 1      // Item is directly pinned
        case tag = 2         // Item is pinned via tag
        case both = 3        // Item is pinned both ways
    }
    
    /// Result of pinned item query with pin type
    struct PinnedItemResult {
        let item: DBClipboardItem
        let pinType: PinType
    }
    
    /// Fetch all pinned items (direct + tag) with a single query
    func fetchAllPinnedItems() throws -> [PinnedItemResult] {
        return try dbQueue?.read { db in
            // Query that gets both direct and tag-pinned items, with pin type indicator
            let sql = """
                SELECT ci.*, 
                    CASE 
                        WHEN ci.is_pinned = 1 AND tag_pinned.item_id IS NOT NULL THEN 3
                        WHEN ci.is_pinned = 1 THEN 1
                        ELSE 2
                    END as pin_type
                FROM clipboard_items ci
                LEFT JOIN (
                    SELECT DISTINCT cit.item_id 
                    FROM clipboard_item_tags cit 
                    JOIN tags t ON cit.tag_id = t.id 
                    WHERE t.is_pinned = 1
                ) tag_pinned ON ci.id = tag_pinned.item_id
                WHERE ci.is_pinned = 1 OR tag_pinned.item_id IS NOT NULL
                ORDER BY ci.position DESC
            """
            
            var results: [PinnedItemResult] = []
            let rows = try Row.fetchAll(db, sql: sql)
            for row in rows {
                let item = try DBClipboardItem(row: row)
                let pinTypeRaw = row["pin_type"] as? Int ?? 1
                let pinType = PinType(rawValue: pinTypeRaw) ?? .direct
                results.append(PinnedItemResult(item: item, pinType: pinType))
            }
            return results
        } ?? []
    }
}

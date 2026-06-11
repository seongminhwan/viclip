import Foundation
import AppKit
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
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
                try db.execute(sql: "PRAGMA temp_store = MEMORY")
                try db.execute(sql: "PRAGMA mmap_size = 268435456")

                // Register custom REGEXP function for regex search
                let regexp = DatabaseFunction("REGEXP", argumentCount: 2, pure: true) { args in
                    guard let pattern = String.fromDatabaseValue(args[0]),
                          let text = String.fromDatabaseValue(args[1]) else {
                        return false
                    }
                    do {
                        let regex = try NSRegularExpression(pattern: pattern, options: [])
                        let range = NSRange(text.startIndex..., in: text)
                        return regex.firstMatch(in: text, options: [], range: range) != nil
                    } catch {
                        return false
                    }
                }
                db.add(function: regexp)
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
                    t.column("alias", .text)
                    t.column("preview_text", .text)
                }
            } else {
                // Migration: add is_pinned if not exists
                let columns = try db.columns(in: "clipboard_items")
                if !columns.contains(where: { $0.name == "is_pinned" }) {
                    try db.execute(sql: "ALTER TABLE clipboard_items ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0")
                }
                // Migration: add alias column if not exists (for rename feature)
                if !columns.contains(where: { $0.name == "alias" }) {
                    try db.execute(sql: "ALTER TABLE clipboard_items ADD COLUMN alias TEXT")
                }
                // Migration: add lightweight preview text for metadata-only list queries
                if !columns.contains(where: { $0.name == "preview_text" }) {
                    try db.execute(sql: "ALTER TABLE clipboard_items ADD COLUMN preview_text TEXT")
                    try backfillPreviewText(in: db)
                }
            }

            // Create indexes
            try db.create(index: "idx_created_at", on: "clipboard_items", columns: ["created_at"], ifNotExists: true)
            try db.create(index: "idx_is_favorite", on: "clipboard_items", columns: ["is_favorite"], ifNotExists: true)
            try db.create(index: "idx_position", on: "clipboard_items", columns: ["position"], ifNotExists: true)
            try db.create(index: "idx_is_pinned", on: "clipboard_items", columns: ["is_pinned"], ifNotExists: true)
            try db.create(index: "idx_alias", on: "clipboard_items", columns: ["alias"], ifNotExists: true)
            try db.create(index: "idx_content_type", on: "clipboard_items", columns: ["content_type"], ifNotExists: true)
            try db.create(index: "idx_content_type_position", on: "clipboard_items", columns: ["content_type", "position"], ifNotExists: true)
            try db.create(index: "idx_source_app_position", on: "clipboard_items", columns: ["source_app", "position"], ifNotExists: true)
            try db.create(index: "idx_source_bundle_position", on: "clipboard_items", columns: ["source_bundle_id", "position"], ifNotExists: true)

            try ensureFTSTable(in: db)

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

    // MARK: - Search Index

    private func itemColumns(tableAlias: String, includeContent: Bool) -> String {
        let contentColumn = includeContent ? "\(tableAlias).content" : "NULL AS content"
        return """
            \(tableAlias).id,
            \(tableAlias).content_type,
            \(contentColumn),
            \(tableAlias).is_external,
            \(tableAlias).content_size,
            \(tableAlias).source_app,
            \(tableAlias).source_bundle_id,
            \(tableAlias).is_favorite,
            \(tableAlias).is_pinned,
            \(tableAlias).position,
            \(tableAlias).created_at,
            \(tableAlias).alias,
            \(tableAlias).preview_text
        """
    }

    private func backfillPreviewText(in db: Database) throws {
        try db.execute(sql: """
            UPDATE clipboard_items
            SET preview_text = '[Image]'
            WHERE content_type = 'image'
              AND (preview_text IS NULL OR preview_text = '')
        """)

        try db.execute(sql: """
            UPDATE clipboard_items
            SET preview_text = '[Rich Text]'
            WHERE content_type = 'richText'
              AND (preview_text IS NULL OR preview_text = '')
        """)

        let rows = try Row.fetchCursor(db, sql: """
            SELECT id, content_type, content
            FROM clipboard_items
            WHERE content_type IN ('text', 'fileURL')
              AND content IS NOT NULL
              AND (preview_text IS NULL OR preview_text = '')
        """)

        while let row = try rows.next() {
            let itemId: String = row["id"]
            let contentType: String = row["content_type"]
            let content: Data? = row["content"]
            guard let preview = previewText(type: contentType, data: content) else { continue }

            try db.execute(
                sql: "UPDATE clipboard_items SET preview_text = ? WHERE id = ?",
                arguments: [preview, itemId]
            )
        }
    }

    private func ensureFTSTable(in db: Database) throws {
        let existingSQL = try String.fetchOne(
            db,
            sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'clipboard_fts'"
        )

        let needsRecreate =
            existingSQL == nil ||
            existingSQL?.contains("content=''") == true ||
            existingSQL?.contains("alias_content") == false

        if needsRecreate {
            try? db.execute(sql: "DROP TABLE IF EXISTS clipboard_fts")
            try createFTSTable(in: db)
            try rebuildFTSIndex(in: db)
            return
        }

        do {
            _ = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_fts")
        } catch {
            try? db.execute(sql: "DROP TABLE IF EXISTS clipboard_fts")
            try createFTSTable(in: db)
            try rebuildFTSIndex(in: db)
        }
    }

    private func createFTSTable(in db: Database) throws {
        try db.execute(sql: """
            CREATE VIRTUAL TABLE clipboard_fts USING fts5(
                text_content,
                alias_content,
                tokenize='unicode61'
            )
        """)
    }

    private func rebuildFTSIndex(in db: Database) throws {
        try db.execute(sql: "DELETE FROM clipboard_fts")

        let rows = try Row.fetchCursor(db, sql: """
            SELECT id, content_type, content, alias
            FROM clipboard_items
            WHERE content_type IN ('text', 'richText', 'fileURL')
               OR (alias IS NOT NULL AND alias != '')
        """)

        while let row = try rows.next() {
            let itemId: String = row["id"]
            let contentType: String = row["content_type"]
            let content: Data? = row["content"]
            let alias: String? = row["alias"]

            try updateFTSIndex(
                in: db,
                itemId: itemId,
                textContent: textContent(type: contentType, data: content),
                alias: alias
            )
        }
    }

    private func textContent(type: String, data: Data?) -> String? {
        guard let data else { return nil }

        switch type {
        case "text", "fileURL":
            return String(data: data, encoding: .utf8)
        case "richText":
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        default:
            return nil
        }
    }

    private func previewText(type: String, data: Data?) -> String? {
        switch type {
        case "text":
            guard let text = textContent(type: type, data: data) else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "[Text]" : String(trimmed.prefix(100))
        case "richText":
            if let text = textContent(type: type, data: data)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return String(text.prefix(100))
            }
            return "[Rich Text]"
        case "image":
            return "[Image]"
        case "fileURL":
            guard let path = textContent(type: type, data: data) else { return nil }
            return "📁 \(URL(fileURLWithPath: path).lastPathComponent)"
        default:
            return nil
        }
    }

    private func existingFTSText(in db: Database, itemId: String) throws -> String? {
        try String.fetchOne(db, sql: """
            SELECT text_content
            FROM clipboard_fts
            WHERE rowid = (SELECT rowid FROM clipboard_items WHERE id = ?)
        """, arguments: [itemId])
    }

    private func searchableTextFromStoredContent(in db: Database, itemId: String) throws -> String? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT content_type, content
            FROM clipboard_items
            WHERE id = ?
              AND content_type IN ('text', 'richText', 'fileURL')
        """, arguments: [itemId]) else {
            return nil
        }

        let contentType: String = row["content_type"]
        let content: Data? = row["content"]
        return textContent(type: contentType, data: content)
    }

    private func deleteFTSIndex(in db: Database, itemId: String) throws {
        try db.execute(
            sql: "DELETE FROM clipboard_fts WHERE rowid = (SELECT rowid FROM clipboard_items WHERE id = ?)",
            arguments: [itemId]
        )
    }

    private func updateFTSIndex(in db: Database, itemId: String, textContent: String?, alias: String?) throws {
        try deleteFTSIndex(in: db, itemId: itemId)

        let searchableText = normalizedSearchText(textContent)
        let searchableAlias = normalizedSearchText(alias)
        guard searchableText != nil || searchableAlias != nil else { return }

        try db.execute(
            sql: """
                INSERT INTO clipboard_fts(rowid, text_content, alias_content)
                SELECT rowid, ?, ? FROM clipboard_items WHERE id = ?
            """,
            arguments: [searchableText ?? "", searchableAlias ?? "", itemId]
        )
    }

    private func normalizedSearchText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func escapedLikePattern(for query: String) -> String {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    private func ftsQuery(for query: String) -> String {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .map { term in
                let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }
            .joined(separator: " AND ")
    }

    private func queryNeedsLikeFallback(_ query: String) -> Bool {
        let specialChars = CharacterSet(charactersIn: "#\"*:^()[]{}~-")
        return query.unicodeScalars.contains { specialChars.contains($0) }
    }

    private func appendKeywordFilter(
        query: String?,
        isRegex: Bool,
        caseSensitive: Bool,
        joins: inout [String],
        conditions: inout [String],
        args: inout [any DatabaseValueConvertible]
    ) {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return
        }

        joins.append("JOIN clipboard_fts ON clipboard_items.rowid = clipboard_fts.rowid")

        if isRegex {
            let pattern = caseSensitive ? query : "(?i)\(query)"
            conditions.append("(clipboard_fts.text_content REGEXP ? OR clipboard_fts.alias_content REGEXP ?)")
            args.append(pattern)
            args.append(pattern)
        } else if caseSensitive {
            conditions.append("(instr(COALESCE(clipboard_fts.text_content, ''), ?) > 0 OR instr(COALESCE(clipboard_fts.alias_content, ''), ?) > 0)")
            args.append(query)
            args.append(query)
        } else if queryNeedsLikeFallback(query) {
            let pattern = escapedLikePattern(for: query)
            conditions.append("(clipboard_fts.text_content LIKE ? ESCAPE '\\' OR clipboard_fts.alias_content LIKE ? ESCAPE '\\')")
            args.append(pattern)
            args.append(pattern)
        } else {
            let matchQuery = ftsQuery(for: query)
            guard !matchQuery.isEmpty else { return }
            conditions.append("clipboard_fts MATCH ?")
            args.append(matchQuery)
        }
    }

    private func appendContentTypeFilter(
        contentType: String?,
        conditions: inout [String],
        args: inout [any DatabaseValueConvertible]
    ) {
        guard let contentType else { return }
        if contentType == "text" {
            conditions.append("clipboard_items.content_type IN ('text', 'richText')")
        } else {
            conditions.append("clipboard_items.content_type = ?")
            args.append(contentType)
        }
    }

    private func appendTagFilter(
        tagIds: [String]?,
        matchMode: TagMatchMode = .any,
        conditions: inout [String],
        args: inout [any DatabaseValueConvertible]
    ) {
        guard let tagIds, !tagIds.isEmpty else { return }

        let placeholders = tagIds.map { _ in "?" }.joined(separator: ", ")
        if matchMode == .all {
            conditions.append("""
                clipboard_items.id IN (
                    SELECT item_id FROM clipboard_item_tags
                    WHERE tag_id IN (\(placeholders))
                    GROUP BY item_id
                    HAVING COUNT(DISTINCT tag_id) = ?
                )
            """)
            args.append(contentsOf: tagIds)
            args.append(tagIds.count)
        } else {
            conditions.append("""
                clipboard_items.id IN (
                    SELECT item_id FROM clipboard_item_tags
                    WHERE tag_id IN (\(placeholders))
                )
            """)
            args.append(contentsOf: tagIds)
        }
    }

    private func fetchItems(
        db: Database,
        joins: [String],
        conditions: [String],
        args: [any DatabaseValueConvertible],
        limit: Int,
        offset: Int? = nil,
        beforePosition: Int? = nil
    ) throws -> [DBClipboardItem] {
        var effectiveConditions = conditions
        var queryArgs = args

        if let beforePosition {
            effectiveConditions.append("clipboard_items.position < ?")
            queryArgs.append(beforePosition)
        }

        let joinClause = joins.joined(separator: "\n")
        let whereClause = effectiveConditions.isEmpty ? "" : "WHERE " + effectiveConditions.joined(separator: " AND ")
        let limitClause = offset == nil ? "LIMIT ?" : "LIMIT ? OFFSET ?"
        let sql = """
            SELECT \(itemColumns(tableAlias: "clipboard_items", includeContent: false))
            FROM clipboard_items
            \(joinClause)
            \(whereClause)
            ORDER BY clipboard_items.position DESC
            \(limitClause)
        """

        queryArgs.append(limit)
        if let offset {
            queryArgs.append(offset)
        }
        return try DBClipboardItem.fetchAll(db, sql: sql, arguments: StatementArguments(queryArgs))
    }

    // MARK: - CRUD Operations

    func insertItem(_ item: DBClipboardItem, searchText: String? = nil) throws {
        try dbQueue?.write { db in
            try item.insert(db)

            try updateFTSIndex(
                in: db,
                itemId: item.id,
                textContent: searchText ?? item.textContent,
                alias: item.alias
            )
        }
    }

    func updateItem(_ item: DBClipboardItem, searchText: String? = nil) throws {
        try dbQueue?.write { db in
            try item.update(db)

            do {
                try updateFTSIndex(
                    in: db,
                    itemId: item.id,
                    textContent: searchText ?? item.textContent,
                    alias: item.alias
                )
            } catch {
                print("Warning: Could not update FTS index: \(error)")
            }
        }
    }

    func updateSearchIndex(itemId: String, textContent: String?, alias: String?) throws {
        try dbQueue?.write { db in
            try updateFTSIndex(in: db, itemId: itemId, textContent: textContent, alias: alias)
        }
    }

    func updatePreviewText(itemId: String, previewText: String?) throws {
        try dbQueue?.write { db in
            try db.execute(
                sql: "UPDATE clipboard_items SET preview_text = ? WHERE id = ?",
                arguments: [previewText, itemId]
            )
        }
    }

    func setFavorite(itemId: String, isFavorite: Bool) throws {
        try dbQueue?.write { db in
            try db.execute(
                sql: "UPDATE clipboard_items SET is_favorite = ? WHERE id = ?",
                arguments: [isFavorite, itemId]
            )
        }
    }

    func setPinned(itemId: String, isPinned: Bool) throws {
        try dbQueue?.write { db in
            try db.execute(
                sql: "UPDATE clipboard_items SET is_pinned = ? WHERE id = ?",
                arguments: [isPinned, itemId]
            )
        }
    }

    func setAlias(itemId: String, alias: String?) throws {
        try dbQueue?.write { db in
            try db.execute(
                sql: "UPDATE clipboard_items SET alias = ? WHERE id = ?",
                arguments: [alias, itemId]
            )

            let text = try existingFTSText(in: db, itemId: itemId)
                ?? searchableTextFromStoredContent(in: db, itemId: itemId)
            try updateFTSIndex(in: db, itemId: itemId, textContent: text, alias: alias)
        }
    }

    func deleteItem(id: String) throws {
        try dbQueue?.write { db in
            do {
                try deleteFTSIndex(in: db, itemId: id)
            } catch {
                print("Warning: Could not delete from FTS index: \(error)")
            }
            try db.execute(sql: "DELETE FROM clipboard_items WHERE id = ?", arguments: [id])
        }
    }

    /// Delete all items from database and rebuild FTS index
    func deleteAllItems() throws {
        try dbQueue?.write { db in
            // Delete all from main table
            try db.execute(sql: "DELETE FROM clipboard_items")

            // Delete all from FTS and recreate
            try? db.execute(sql: "DROP TABLE IF EXISTS clipboard_fts")
            try createFTSTable(in: db)

            // Also clear tags
            try db.execute(sql: "DELETE FROM clipboard_item_tags")
        }
    }

    private func buildFilteredQuery(filter: FilterQuery) -> (joins: [String], conditions: [String], args: [any DatabaseValueConvertible])? {
        guard !filter.contentTypes.isEmpty else { return nil }

        var joins: [String] = []
        var conditions: [String] = []
        var args: [any DatabaseValueConvertible] = []

        appendKeywordFilter(
            query: filter.keyword,
            isRegex: filter.isRegex,
            caseSensitive: filter.caseSensitive,
            joins: &joins,
            conditions: &conditions,
            args: &args
        )

        if filter.contentTypes.count < ContentTypeFilter.allCases.count {
            let placeholders = filter.contentTypes.map { _ in "?" }.joined(separator: ", ")
            conditions.append("clipboard_items.content_type IN (\(placeholders))")
            args.append(contentsOf: filter.contentTypes.map(\.rawValue))
        }

        if !filter.sourceApps.isEmpty {
            let placeholders = filter.sourceApps.map { _ in "?" }.joined(separator: ", ")
            conditions.append("clipboard_items.source_app IN (\(placeholders))")
            args.append(contentsOf: filter.sourceApps)
        }

        if !filter.sourceBundleIds.isEmpty {
            let placeholders = filter.sourceBundleIds.map { _ in "?" }.joined(separator: ", ")
            conditions.append("clipboard_items.source_bundle_id IN (\(placeholders))")
            args.append(contentsOf: filter.sourceBundleIds)
        }

        let dateRange = filter.effectiveDateRange
        if let from = dateRange.from {
            conditions.append("clipboard_items.created_at >= ?")
            args.append(from.timeIntervalSince1970)
        }
        if let to = dateRange.to {
            conditions.append("clipboard_items.created_at <= ?")
            args.append(to.timeIntervalSince1970)
        }

        if filter.favoritesOnly {
            conditions.append("clipboard_items.is_favorite = 1")
        }

        appendTagFilter(
            tagIds: filter.tagIds,
            matchMode: filter.tagMatchMode,
            conditions: &conditions,
            args: &args
        )

        return (joins, conditions, args)
    }

    /// Fetch items with advanced filter
    /// - Parameters:
    ///   - filter: FilterQuery with all filter criteria
    ///   - limit: Max items to return
    ///   - offset: Offset for pagination
    func fetchFilteredItems(filter: FilterQuery, limit: Int = 100, offset: Int = 0) throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            guard let queryParts = buildFilteredQuery(filter: filter) else { return [] }

            return try fetchItems(
                db: db,
                joins: queryParts.joins,
                conditions: queryParts.conditions,
                args: queryParts.args,
                limit: limit,
                offset: offset
            )
        } ?? []
    }

    func fetchFilteredItemsBeforePosition(filter: FilterQuery, limit: Int = 100, beforePosition: Int) throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            guard let queryParts = buildFilteredQuery(filter: filter) else { return [] }

            return try fetchItems(
                db: db,
                joins: queryParts.joins,
                conditions: queryParts.conditions,
                args: queryParts.args,
                limit: limit,
                beforePosition: beforePosition
            )
        } ?? []
    }

    func fetchItem(id: String) throws -> DBClipboardItem? {
        try dbQueue?.read { db in
            try DBClipboardItem.fetchOne(db, sql: """
                SELECT \(itemColumns(tableAlias: "clipboard_items", includeContent: true))
                FROM clipboard_items
                WHERE id = ?
            """, arguments: [id])
        }
    }

    /// Get distinct source apps from the database
    func fetchDistinctSourceApps() throws -> [String] {
        try dbQueue?.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT source_app FROM clipboard_items WHERE source_app IS NOT NULL ORDER BY source_app")
        } ?? []
    }

    /// Get the maximum position value in the database
    func maxPosition() throws -> Int {
        try dbQueue?.read { db in
            try Int.fetchOne(db, sql: "SELECT MAX(position) FROM clipboard_items") ?? 0
        } ?? 0
    }

    /// Get the offset (0-based index) of an item in the sorted list
    /// Items are sorted by position DESC, so this counts items with higher position
    func getItemRankOffset(itemId: String) throws -> Int? {
        try dbQueue?.read { db in
            // First get the item's position
            guard let itemPosition = try Int.fetchOne(db, sql:
                "SELECT position FROM clipboard_items WHERE id = ?", arguments: [itemId]) else {
                return nil
            }
            // Count items with higher position (they come before in DESC order)
            let offset = try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM clipboard_items WHERE position > ?", arguments: [itemPosition]) ?? 0
            return offset
        }
    }

    /// Unified interface for fetching items with optional search
    /// - Parameters:
    ///   - limit: Max items to return
    ///   - offset: Offset for pagination
    ///   - query: Optional search query (nil = browse all, non-nil = search)
    ///   - tagIds: Optional tag IDs to filter by (nil = no filter, empty = no filter, non-empty = items must have ANY of these tags)
    ///   - contentType: Optional content type filter (nil = all types)
    ///   - isRegex: Whether to treat query as a regex pattern
    private func buildItemQuery(
        query: String?,
        tagIds: [String]?,
        contentType: String?,
        isRegex: Bool
    ) -> (joins: [String], conditions: [String], args: [any DatabaseValueConvertible]) {
        var joins: [String] = []
        var conditions: [String] = []
        var args: [any DatabaseValueConvertible] = []

        appendKeywordFilter(
            query: query,
            isRegex: isRegex,
            caseSensitive: false,
            joins: &joins,
            conditions: &conditions,
            args: &args
        )
        appendContentTypeFilter(contentType: contentType, conditions: &conditions, args: &args)
        appendTagFilter(tagIds: tagIds, conditions: &conditions, args: &args)

        return (joins, conditions, args)
    }

    func fetchItems(limit: Int = 100, offset: Int = 0, query: String? = nil, tagIds: [String]? = nil, contentType: String? = nil, isRegex: Bool = false) throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            let queryParts = buildItemQuery(
                query: query,
                tagIds: tagIds,
                contentType: contentType,
                isRegex: isRegex
            )

            return try fetchItems(
                db: db,
                joins: queryParts.joins,
                conditions: queryParts.conditions,
                args: queryParts.args,
                limit: limit,
                offset: offset
            )
        } ?? []
    }

    func fetchItemsBeforePosition(limit: Int = 100, beforePosition: Int, query: String? = nil, tagIds: [String]? = nil, contentType: String? = nil, isRegex: Bool = false) throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            let queryParts = buildItemQuery(
                query: query,
                tagIds: tagIds,
                contentType: contentType,
                isRegex: isRegex
            )

            return try fetchItems(
                db: db,
                joins: queryParts.joins,
                conditions: queryParts.conditions,
                args: queryParts.args,
                limit: limit,
                beforePosition: beforePosition
            )
        } ?? []
    }

    func fetchFavorites() throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            try DBClipboardItem.fetchAll(db, sql: """
                SELECT \(itemColumns(tableAlias: "clipboard_items", includeContent: false))
                FROM clipboard_items
                WHERE is_favorite = 1
                ORDER BY position DESC
            """)
        } ?? []
    }

    func searchItems(query: String, limit: Int = 100) throws -> [DBClipboardItem] {
        try fetchItems(limit: limit, offset: 0, query: query)
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

    func getExternalItemsNeedingSearchRepair() throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            try DBClipboardItem.fetchAll(db, sql: """
                SELECT \(itemColumns(tableAlias: "ci", includeContent: false))
                FROM clipboard_items ci
                LEFT JOIN clipboard_fts fts ON ci.rowid = fts.rowid
                WHERE ci.is_external = 1
                  AND (
                    ci.preview_text IS NULL
                    OR ci.preview_text = ''
                    OR (
                        ci.content_type IN ('text', 'richText', 'fileURL')
                        AND (fts.rowid IS NULL OR fts.text_content IS NULL OR fts.text_content = '')
                    )
                  )
            """)
        } ?? []
    }

    // MARK: - Retention Queries

    /// Fetch items older than the specified date
    func fetchItemsOlderThan(date: Date) throws -> [DBClipboardItem] {
        let timestamp = date.timeIntervalSince1970
        return try dbQueue?.read { db in
            try DBClipboardItem.fetchAll(db, sql: """
                SELECT \(itemColumns(tableAlias: "clipboard_items", includeContent: false))
                FROM clipboard_items
                WHERE created_at < ?
                ORDER BY created_at ASC
            """, arguments: [timestamp])
        } ?? []
    }

    /// Fetch the oldest items (for enforcing item limit)
    func fetchOldestItems(limit: Int) throws -> [DBClipboardItem] {
        try dbQueue?.read { db in
            try DBClipboardItem.fetchAll(db, sql: """
                SELECT \(itemColumns(tableAlias: "clipboard_items", includeContent: false))
                FROM clipboard_items
                ORDER BY created_at ASC
                LIMIT ?
            """, arguments: [limit])
        } ?? []
    }

    // MARK: - Migration

    func migrateFromJSON(items: [ClipboardItem]) throws {
        try dbQueue?.write { db in
            for item in items {
                let dbItem = DBClipboardItem(from: item)
                try dbItem.insert(db)
                try updateFTSIndex(in: db, itemId: dbItem.id, textContent: dbItem.textContent, alias: dbItem.alias)
            }
        }
    }

    func clearAll() throws {
        try dbQueue?.write { db in
            try db.execute(sql: "DELETE FROM clipboard_fts")
            try db.execute(sql: "DELETE FROM clipboard_items")
            try db.execute(sql: "DELETE FROM favorite_groups")
            try db.execute(sql: "DELETE FROM clipboard_item_tags")
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
    var alias: String?  // User-defined alias/name for the item
    var previewText: String?

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
        case alias
        case previewText = "preview_text"
    }

    // Helper to extract text for FTS
    var textContent: String? {
        guard let data = content else { return nil }

        switch contentType {
        case "text", "fileURL":
            return String(data: data, encoding: .utf8)
        case "richText":
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        default:
            return nil
        }
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
        self.alias = item.alias
        self.previewText = item.previewText ?? item.content.preview

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
            isDirectPinned: isPinned,
            alias: alias,
            previewText: previewText,
            isContentLoaded: true
        )
    }

    func toClipboardItemSummary() -> ClipboardItem? {
        guard let uuid = UUID(uuidString: id) else { return nil }

        let clipboardContent: ClipboardContent
        switch contentType {
        case "text":
            clipboardContent = .text(previewText ?? "")
        case "richText":
            clipboardContent = .richText(Data())
        case "image":
            clipboardContent = .image(Data())
        case "fileURL":
            clipboardContent = .fileURL(previewText ?? "")
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
            isDirectPinned: isPinned,
            alias: alias,
            previewText: previewText,
            isContentLoaded: false
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

    func fetchTagIdsForItems(itemIds: [String]) throws -> [String: Set<String>] {
        guard !itemIds.isEmpty else { return [:] }

        return try dbQueue?.read { db in
            let placeholders = itemIds.map { _ in "?" }.joined(separator: ", ")
            let rows = try Row.fetchAll(db, sql: """
                SELECT item_id, tag_id
                FROM clipboard_item_tags
                WHERE item_id IN (\(placeholders))
            """, arguments: StatementArguments(itemIds))

            var result: [String: Set<String>] = [:]
            for row in rows {
                let itemId: String = row["item_id"]
                let tagId: String = row["tag_id"]
                result[itemId, default: []].insert(tagId)
            }
            return result
        } ?? [:]
    }

    func fetchItemsWithTags(tagIds: [String]) throws -> [DBClipboardItem] {
        guard !tagIds.isEmpty else { return try fetchItems() }

        return try dbQueue?.read { db in
            let placeholders = tagIds.map { _ in "?" }.joined(separator: ", ")
            let sql = """
                SELECT DISTINCT \(itemColumns(tableAlias: "ci", includeContent: false))
                FROM clipboard_items ci
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
                SELECT \(itemColumns(tableAlias: "ci", includeContent: false)),
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

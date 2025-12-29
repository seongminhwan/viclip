import Foundation
import Combine

// MARK: - Tag Model (View Layer)
struct Tag: Identifiable, Equatable {
    let id: String
    var name: String
    var color: String?
    var position: Int
    var isPinned: Bool
    let createdAt: Date
    
    init(id: String = UUID().uuidString, name: String, color: String? = nil, position: Int = 0, isPinned: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.color = color
        self.position = position
        self.isPinned = isPinned
        self.createdAt = createdAt
    }
    
    init(from dbTag: DBTag) {
        self.id = dbTag.id
        self.name = dbTag.name
        self.color = dbTag.color
        self.position = dbTag.position
        self.isPinned = dbTag.isPinned
        self.createdAt = Date(timeIntervalSince1970: dbTag.createdAt)
    }
    
    func toDBTag() -> DBTag {
        DBTag(id: id, name: name, color: color, position: position, isPinned: isPinned)
    }
}

// MARK: - Tag Service
class TagService: ObservableObject {
    static let shared = TagService()
    
    @Published var tags: [Tag] = []
    @Published var selectedTagIds: Set<String> = []
    @Published var isLoading: Bool = false
    
    private let database = DatabaseManager.shared
    
    private init() {
        loadTags()
    }
    
    // MARK: - Load Tags
    
    func loadTags() {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let dbTags = try database.fetchAllTags()
            tags = dbTags.map { Tag(from: $0) }
        } catch {
            print("Error loading tags: \(error)")
        }
    }
    
    // MARK: - Create Tag
    
    @discardableResult
    func createTag(name: String, color: String? = nil) -> Tag? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        
        // Check for duplicate names
        do {
            if try database.tagExists(name: trimmedName) {
                print("Tag with name '\(trimmedName)' already exists")
                return nil
            }
        } catch {
            print("Error checking tag existence: \(error)")
            return nil
        }
        
        let newTag = Tag(name: trimmedName, color: color, position: tags.count + 1)
        
        do {
            try database.insertTag(newTag.toDBTag())
            loadTags()  // Reload to get correct positions
            return tags.first { $0.id == newTag.id }
        } catch {
            print("Error creating tag: \(error)")
            return nil
        }
    }
    
    // MARK: - Rename Tag
    
    func renameTag(id: String, newName: String) -> Bool {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        
        guard var tag = tags.first(where: { $0.id == id }) else { return false }
        
        // Check for duplicate names (excluding current tag)
        if tags.contains(where: { $0.id != id && $0.name.lowercased() == trimmedName.lowercased() }) {
            print("Tag with name '\(trimmedName)' already exists")
            return false
        }
        
        tag.name = trimmedName
        
        do {
            try database.updateTag(tag.toDBTag())
            loadTags()
            return true
        } catch {
            print("Error renaming tag: \(error)")
            return false
        }
    }
    
    // MARK: - Delete Tag
    
    @discardableResult
    func deleteTag(id: String, cascadeDeleteItems: Bool = false) -> Bool {
        do {
            if cascadeDeleteItems {
                // Get all items with this tag and delete them
                let itemIds = try database.fetchItemsWithTags(tagIds: [id]).map { $0.id }
                for itemId in itemIds {
                    try database.deleteItem(id: itemId)
                }
            }
            
            try database.deleteTag(id: id)
            selectedTagIds.remove(id)
            loadTags()
            return true
        } catch {
            print("Error deleting tag: \(error)")
            return false
        }
    }
    
    // MARK: - Tag Selection
    
    func toggleTagSelection(id: String) {
        if selectedTagIds.contains(id) {
            selectedTagIds.remove(id)
        } else {
            selectedTagIds.insert(id)
        }
    }
    
    func selectTag(id: String) {
        selectedTagIds.insert(id)
    }
    
    func deselectTag(id: String) {
        selectedTagIds.remove(id)
    }
    
    func clearSelection() {
        selectedTagIds.removeAll()
    }
    
    func isSelected(id: String) -> Bool {
        selectedTagIds.contains(id)
    }
    
    // MARK: - Pin Operations
    
    /// Toggle pin state of a tag
    @discardableResult
    func togglePin(id: String) -> Bool {
        guard var tag = tags.first(where: { $0.id == id }) else { return false }
        
        tag.isPinned.toggle()
        
        do {
            try database.updateTag(tag.toDBTag())
            loadTags()
            return true
        } catch {
            print("Error toggling pin: \(error)")
            return false
        }
    }
    
    /// Get all pinned tags
    var pinnedTags: [Tag] {
        tags.filter { $0.isPinned }
    }
    
    /// Get IDs of all pinned tags
    var pinnedTagIds: [String] {
        pinnedTags.map { $0.id }
    }
    
    // MARK: - Item-Tag Operations
    
    func getTagsForItem(itemId: String) -> [Tag] {
        do {
            let dbTags = try database.fetchTagsForItem(itemId: itemId)
            return dbTags.map { Tag(from: $0) }
        } catch {
            print("Error getting tags for item: \(error)")
            return []
        }
    }
    
    func setTagsForItem(itemId: String, tagIds: Set<String>) {
        do {
            try database.setTagsForItem(itemId: itemId, tagIds: tagIds)
        } catch {
            print("Error setting tags for item: \(error)")
        }
    }
    
    func addTagToItem(itemId: String, tagId: String) {
        do {
            try database.addTagToItem(itemId: itemId, tagId: tagId)
        } catch {
            print("Error adding tag to item: \(error)")
        }
    }
    
    func removeTagFromItem(itemId: String, tagId: String) {
        do {
            try database.removeTagFromItem(itemId: itemId, tagId: tagId)
        } catch {
            print("Error removing tag from item: \(error)")
        }
    }
}

import Foundation
import AppKit

// MARK: - Clipboard Content Types
enum ClipboardContent: Codable, Equatable {
    case text(String)
    case richText(Data)  // RTF data
    case image(Data)     // PNG/JPEG data
    case fileURL(String) // File path
    
    var preview: String {
        switch self {
        case .text(let string):
            // Trim leading/trailing whitespace for cleaner list display
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(100))
        case .richText:
            return "[Rich Text]"
        case .image:
            return "[Image]"
        case .fileURL(let path):
            return "📁 \(URL(fileURLWithPath: path).lastPathComponent)"
        }
    }
    
    var icon: String {
        switch self {
        case .text:
            return "doc.text"
        case .richText:
            return "doc.richtext"
        case .image:
            return "photo"
        case .fileURL:
            return "folder"
        }
    }
    
    var dataSize: Int {
        switch self {
        case .text(let string):
            return string.utf8.count
        case .richText(let data):
            return data.count
        case .image(let data):
            return data.count
        case .fileURL(let path):
            return path.utf8.count
        }
    }
}

// MARK: - Pin Type
enum PinType: Int, Codable {
    case none = 0    // Not pinned
    case direct = 1  // Directly pinned (orange)
    case tag = 2     // Pinned via tag (blue)
    case both = 3    // Both direct and tag (purple)
}

// MARK: - Clipboard Item
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var content: ClipboardContent
    let sourceApp: String?
    let sourceAppBundleId: String?
    let createdAt: Date
    let position: Int  // Sequential position for context
    var isFavorite: Bool
    var groupId: UUID?
    var isExternallyStored: Bool  // Content stored in external file
    var contentSize: Int  // Size in bytes
    var virtualId: String?  // For pinned items, uses "PIN_<uuid>" format
    var isDirectPinned: Bool  // Whether this item is directly pinned
    var pinType: PinType  // Pin type for color differentiation
    
    /// The ID used for SwiftUI's ForEach/List identification
    var displayId: String {
        virtualId ?? id.uuidString
    }
    
    /// Whether this is a pinned virtual item (from tag) or directly pinned
    var isPinnedItem: Bool {
        pinType != .none || (virtualId?.hasPrefix("PIN_") ?? false)
    }
    
    /// The original UUID (without PIN_ prefix)
    var originalId: UUID {
        if let virtualId = virtualId, virtualId.hasPrefix("PIN_") {
            let uuidString = String(virtualId.dropFirst(4))
            return UUID(uuidString: uuidString) ?? id
        }
        return id
    }
    
    enum CodingKeys: String, CodingKey {
        case id, content, sourceApp, sourceAppBundleId, createdAt, position
        case isFavorite, groupId, isExternallyStored, contentSize, isDirectPinned
        // virtualId and pinType are runtime only
    }
    
    init(
        id: UUID = UUID(),
        content: ClipboardContent,
        sourceApp: String? = nil,
        sourceAppBundleId: String? = nil,
        createdAt: Date = Date(),
        position: Int = 0,
        isFavorite: Bool = false,
        groupId: UUID? = nil,
        isExternallyStored: Bool = false,
        contentSize: Int = 0,
        virtualId: String? = nil,
        isDirectPinned: Bool = false,
        pinType: PinType = .none
    ) {
        self.id = id
        self.content = content
        self.sourceApp = sourceApp
        self.sourceAppBundleId = sourceAppBundleId
        self.createdAt = createdAt
        self.position = position
        self.isFavorite = isFavorite
        self.groupId = groupId
        self.isExternallyStored = isExternallyStored
        self.contentSize = contentSize > 0 ? contentSize : content.dataSize
        self.virtualId = virtualId
        self.isDirectPinned = isDirectPinned
        self.pinType = pinType
    }
    
    // Custom decoder to handle legacy JSON without new fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(ClipboardContent.self, forKey: .content)
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        sourceAppBundleId = try container.decodeIfPresent(String.self, forKey: .sourceAppBundleId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        groupId = try container.decodeIfPresent(UUID.self, forKey: .groupId)
        
        // New fields with defaults for legacy data
        isExternallyStored = try container.decodeIfPresent(Bool.self, forKey: .isExternallyStored) ?? false
        contentSize = try container.decodeIfPresent(Int.self, forKey: .contentSize) ?? content.dataSize
        isDirectPinned = try container.decodeIfPresent(Bool.self, forKey: .isDirectPinned) ?? false
        
        // Runtime-only fields
        virtualId = nil
        pinType = .none
    }
    
    var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(contentSize), countStyle: .file)
    }
}

// MARK: - Favorite Group
struct FavoriteGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String
    var order: Int
    
    init(id: UUID = UUID(), name: String, icon: String = "folder", order: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.order = order
    }
}

// MARK: - Privacy Rule
struct PrivacyRule: Identifiable, Codable, Equatable {
    let id: UUID
    var appBundleId: String?    // Exclude specific app
    var keyword: String?         // Exclude content containing keyword
    var isEnabled: Bool
    
    init(id: UUID = UUID(), appBundleId: String? = nil, keyword: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.appBundleId = appBundleId
        self.keyword = keyword
        self.isEnabled = isEnabled
    }
    
    var description: String {
        if let bundleId = appBundleId {
            return "App: \(bundleId)"
        } else if let keyword = keyword {
            return "Keyword: \(keyword)"
        }
        return "Unknown rule"
    }
}

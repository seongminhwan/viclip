import Foundation
import AppKit

/// Service for generating and caching image thumbnails
/// Reduces memory usage by storing small thumbnails for list display
class ThumbnailService {
    static let shared = ThumbnailService()
    
    // In-memory cache for thumbnails (LRU behavior via NSCache)
    private let cache = NSCache<NSString, NSImage>()
    
    // Thumbnail settings
    private let thumbnailSize: CGFloat = 80  // Size for list thumbnails
    private let maxCacheCount = 200  // Max thumbnails in memory
    
    private init() {
        cache.countLimit = maxCacheCount
    }
    
    /// Get thumbnail for image data, generating if needed
    func thumbnail(for imageData: Data, id: String) -> NSImage? {
        let cacheKey = id as NSString
        
        // Check cache first
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        // Generate thumbnail
        guard let original = NSImage(data: imageData) else { return nil }
        
        let thumbnail = generateThumbnail(from: original)
        
        // Cache it
        if let thumb = thumbnail {
            cache.setObject(thumb, forKey: cacheKey)
        }
        
        return thumbnail
    }
    
    /// Generate a thumbnail from an NSImage
    private func generateThumbnail(from image: NSImage) -> NSImage? {
        let originalSize = image.size
        
        // Skip if already small enough
        if originalSize.width <= thumbnailSize && originalSize.height <= thumbnailSize {
            return image
        }
        
        // Calculate scaled size maintaining aspect ratio
        let scale: CGFloat
        if originalSize.width > originalSize.height {
            scale = thumbnailSize / originalSize.width
        } else {
            scale = thumbnailSize / originalSize.height
        }
        
        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
        
        // Create thumbnail
        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        
        thumbnail.unlockFocus()
        
        return thumbnail
    }
    
    /// Clear all cached thumbnails
    func clearCache() {
        cache.removeAllObjects()
    }
    
    /// Remove specific thumbnail from cache
    func removeFromCache(id: String) {
        cache.removeObject(forKey: id as NSString)
    }
}

import Foundation

// MARK: - Sequential Paster
class SequentialPaster: ObservableObject {
    static let shared = SequentialPaster()
    
    @Published var isActive: Bool = false
    @Published var queue: [ClipboardItem] = []
    @Published var currentIndex: Int = 0
    
    private let clipboardMonitor: ClipboardMonitor
    
    init(clipboardMonitor: ClipboardMonitor = .shared) {
        self.clipboardMonitor = clipboardMonitor
    }
    
    var hasItems: Bool {
        !queue.isEmpty && currentIndex < queue.count
    }
    
    var currentItem: ClipboardItem? {
        guard hasItems else { return nil }
        return queue[currentIndex]
    }
    
    var remainingCount: Int {
        max(0, queue.count - currentIndex)
    }
    
    // MARK: - Queue Management
    
    func addToQueue(_ item: ClipboardItem) {
        queue.append(item)
        if !isActive {
            isActive = true
        }
    }
    
    func addMultipleToQueue(_ items: [ClipboardItem]) {
        queue.append(contentsOf: items)
        if !isActive && !items.isEmpty {
            isActive = true
        }
    }
    
    func removeFromQueue(_ item: ClipboardItem) {
        queue.removeAll { $0.id == item.id }
        if queue.isEmpty {
            reset()
        }
    }
    
    func clearQueue() {
        queue.removeAll()
        reset()
    }
    
    // MARK: - Pasting
    
    func pasteNext() -> Bool {
        guard let item = currentItem else {
            reset()
            return false
        }
        
        clipboardMonitor.paste(item: item)
        currentIndex += 1
        
        // Check if queue is exhausted
        if currentIndex >= queue.count {
            reset()
        }
        
        return true
    }
    
    func peekNext() -> ClipboardItem? {
        let nextIndex = currentIndex + 1
        guard nextIndex < queue.count else { return nil }
        return queue[nextIndex]
    }
    
    // MARK: - Control
    
    func reset() {
        isActive = false
        queue.removeAll()
        currentIndex = 0
    }
    
    func toggleActive() {
        if isActive {
            reset()
        } else if !queue.isEmpty {
            isActive = true
        }
    }
}

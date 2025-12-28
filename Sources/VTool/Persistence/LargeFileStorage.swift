import Foundation

// MARK: - Storage Settings
class StorageSettings: ObservableObject {
    static let shared = StorageSettings()
    
    @Published var enableExternalStorage: Bool {
        didSet {
            UserDefaults.standard.set(enableExternalStorage, forKey: "enableExternalStorage")
        }
    }
    
    @Published var largeFileThreshold: Int {
        didSet {
            UserDefaults.standard.set(largeFileThreshold, forKey: "largeFileThreshold")
        }
    }
    
    @Published var maxHistoryCount: Int {
        didSet {
            UserDefaults.standard.set(maxHistoryCount, forKey: "maxHistoryCount")
        }
    }
    
    private init() {
        self.enableExternalStorage = UserDefaults.standard.bool(forKey: "enableExternalStorage")
        self.largeFileThreshold = UserDefaults.standard.integer(forKey: "largeFileThreshold")
        self.maxHistoryCount = UserDefaults.standard.integer(forKey: "maxHistoryCount")
        
        // Set defaults if not configured
        if largeFileThreshold == 0 {
            largeFileThreshold = 1_048_576  // 1MB default
        }
        if maxHistoryCount == 0 {
            maxHistoryCount = 10_000
        }
    }
    
    // Human-readable threshold
    var thresholdDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(largeFileThreshold), countStyle: .file)
    }
}

// MARK: - Large File Storage
class LargeFileStorage {
    static let shared = LargeFileStorage()
    
    private let fileManager = FileManager.default
    
    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let largeFilesDir = appSupport.appendingPathComponent("VTool/large_files", isDirectory: true)
        
        if !fileManager.fileExists(atPath: largeFilesDir.path) {
            try? fileManager.createDirectory(at: largeFilesDir, withIntermediateDirectories: true)
        }
        
        return largeFilesDir
    }
    
    private init() {}
    
    // MARK: - File Operations
    
    func store(content: Data, for itemId: String) throws {
        let fileURL = storageDirectory.appendingPathComponent("\(itemId).dat")
        try content.write(to: fileURL, options: .atomic)
    }
    
    func retrieve(for itemId: String) -> Data? {
        let fileURL = storageDirectory.appendingPathComponent("\(itemId).dat")
        return try? Data(contentsOf: fileURL)
    }
    
    func delete(for itemId: String) {
        let fileURL = storageDirectory.appendingPathComponent("\(itemId).dat")
        try? fileManager.removeItem(at: fileURL)
    }
    
    func exists(for itemId: String) -> Bool {
        let fileURL = storageDirectory.appendingPathComponent("\(itemId).dat")
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    // MARK: - Statistics
    
    func externalFileCount() -> Int {
        let files = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)
        return files?.filter { $0.pathExtension == "dat" }.count ?? 0
    }
    
    func totalExternalSize() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for file in files where file.pathExtension == "dat" {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }
    
    func allExternalFileIds() -> [String] {
        guard let files = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "dat" }.map { $0.deletingPathExtension().lastPathComponent }
    }
    
    // MARK: - Migration
    
    func migrateToDatabase(itemId: String) -> Data? {
        // Retrieve content and delete file
        guard let data = retrieve(for: itemId) else { return nil }
        delete(for: itemId)
        return data
    }
    
    func deleteAllExternalFiles() {
        for fileId in allExternalFileIds() {
            delete(for: fileId)
        }
    }
}

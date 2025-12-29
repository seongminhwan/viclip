import Foundation
import CloudKit

class CloudKitSync: ObservableObject {
    static let shared = CloudKitSync()
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let recordType = "ClipboardItem"
    
    private init() {
        container = CKContainer(identifier: "iCloud.com.vtool.clipboard")
        privateDatabase = container.privateCloudDatabase
    }
    
    // MARK: - Sync Operations
    
    func syncItems(_ items: [ClipboardItem]) async throws {
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else { return }
        
        await MainActor.run { isSyncing = true }
        defer { Task { @MainActor in isSyncing = false } }
        
        // Convert items to CKRecords
        let records = items.prefix(100).map { createRecord(from: $0) } // Limit to 100 for sync
        
        // Batch save
        let operation = CKModifyRecordsOperation(recordsToSave: Array(records), recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        
        _ = try await privateDatabase.modifyRecords(saving: Array(records), deleting: [])
        
        await MainActor.run {
            lastSyncDate = Date()
            syncError = nil
        }
    }
    
    func fetchItems() async throws -> [ClipboardItem] {
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else { return [] }
        
        await MainActor.run { isSyncing = true }
        defer { Task { @MainActor in isSyncing = false } }
        
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        let (results, _) = try await privateDatabase.records(matching: query, resultsLimit: 100)
        
        var items: [ClipboardItem] = []
        for (_, result) in results {
            if case .success(let record) = result,
               let item = createItem(from: record) {
                items.append(item)
            }
        }
        
        await MainActor.run {
            lastSyncDate = Date()
            syncError = nil
        }
        
        return items
    }
    
    func deleteItem(id: UUID) async throws {
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else { return }
        
        let recordID = CKRecord.ID(recordName: id.uuidString)
        try await privateDatabase.deleteRecord(withID: recordID)
    }
    
    // MARK: - Record Conversion
    
    private func createRecord(from item: ClipboardItem) -> CKRecord {
        let recordID = CKRecord.ID(recordName: item.id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        
        record["createdAt"] = item.createdAt
        record["sourceApp"] = item.sourceApp
        record["sourceAppBundleId"] = item.sourceAppBundleId
        record["position"] = item.position
        record["isFavorite"] = item.isFavorite
        record["groupId"] = item.groupId?.uuidString
        
        // Encode content
        switch item.content {
        case .text(let string):
            record["contentType"] = "text"
            record["textContent"] = string
        case .richText(let data):
            record["contentType"] = "richText"
            record["dataContent"] = data
        case .image(let data):
            record["contentType"] = "image"
            // For images, use CKAsset for larger data
            if let tempURL = saveToTempFile(data: data, name: item.id.uuidString) {
                record["imageAsset"] = CKAsset(fileURL: tempURL)
            }
        case .fileURL(let path):
            record["contentType"] = "fileURL"
            record["textContent"] = path
        }
        
        return record
    }
    
    private func createItem(from record: CKRecord) -> ClipboardItem? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let createdAt = record["createdAt"] as? Date,
              let contentType = record["contentType"] as? String else {
            return nil
        }
        
        let content: ClipboardContent
        switch contentType {
        case "text":
            guard let text = record["textContent"] as? String else { return nil }
            content = .text(text)
        case "richText":
            guard let data = record["dataContent"] as? Data else { return nil }
            content = .richText(data)
        case "image":
            if let asset = record["imageAsset"] as? CKAsset,
               let url = asset.fileURL,
               let data = try? Data(contentsOf: url) {
                content = .image(data)
            } else {
                return nil
            }
        case "fileURL":
            guard let path = record["textContent"] as? String else { return nil }
            content = .fileURL(path)
        default:
            return nil
        }
        
        return ClipboardItem(
            id: id,
            content: content,
            sourceApp: record["sourceApp"] as? String,
            sourceAppBundleId: record["sourceAppBundleId"] as? String,
            createdAt: createdAt,
            position: (record["position"] as? Int) ?? 0,
            isFavorite: (record["isFavorite"] as? Bool) ?? false,
            groupId: (record["groupId"] as? String).flatMap { UUID(uuidString: $0) }
        )
    }
    
    private func saveToTempFile(data: Data, name: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(name).png")
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }
    
    // MARK: - Subscription
    
    func setupSubscription() async throws {
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: "clipboard-changes",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        
        try await privateDatabase.save(subscription)
    }
}

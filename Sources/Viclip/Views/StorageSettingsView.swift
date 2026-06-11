import SwiftUI

// MARK: - Storage Settings View
struct StorageSettingsView: View {
    @ObservedObject private var storageSettings = StorageSettings.shared
    @ObservedObject private var clipboardMonitor = ClipboardMonitor.shared
    @ObservedObject private var languageManager = AppLanguageManager.shared
    
    // Retention settings (migrated from General settings)
    @AppStorage("retentionMaxItemsEnabled") private var retentionMaxItemsEnabled = false
    @AppStorage("retentionMaxItems") private var retentionMaxItems = 1000
    @AppStorage("retentionMaxAgeEnabled") private var retentionMaxAgeEnabled = false
    @AppStorage("retentionMaxAgeDays") private var retentionMaxAgeDays = 30
    
    @State private var showMigrationDialog = false
    @State private var showClearConfirmation = false
    @State private var migrationAction: MigrationAction = .none
    
    enum MigrationAction {
        case none
        case enableExternal
        case disableExternal
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Statistics Card
                SettingsCard(title: L10n.t("storage.databaseStats", "Database Statistics"), icon: "chart.bar.fill") {
                    HStack(spacing: 24) {
                        StatItem(
                            value: "\(clipboardMonitor.itemCount)",
                            label: L10n.t("storage.items", "Items"),
                            icon: "doc.on.doc"
                        )
                        
                        Divider()
                            .frame(height: 40)
                        
                        StatItem(
                            value: ByteCountFormatter.string(fromByteCount: clipboardMonitor.totalSize, countStyle: .file),
                            label: L10n.t("storage.totalSize", "Total Size"),
                            icon: "internaldrive"
                        )
                        
                        Divider()
                            .frame(height: 40)
                        
                        StatItem(
                            value: "\(clipboardMonitor.externalFileCount)",
                            label: L10n.t("storage.external", "External"),
                            icon: "folder"
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // History Limit Card (Auto-Cleanup)
                SettingsCard(title: L10n.t("storage.historyLimit", "History Limit"), icon: "clock.arrow.circlepath") {
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(L10n.t("storage.autoDeleteHint", "Automatically delete old items to save storage. Disabled by default."))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        Divider()
                        
                        // Max Items Limit
                        VStack(spacing: 8) {
                            HStack {
                                Toggle("", isOn: $retentionMaxItemsEnabled)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                Text(L10n.t("storage.limitTotal", "Limit total saved items"))
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            
                            if retentionMaxItemsEnabled {
                                HStack {
                                    Text(L10n.t("storage.keepAtMost", "Keep at most:"))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Picker("", selection: $retentionMaxItems) {
                                        Text("500").tag(500)
                                        Text("1,000").tag(1000)
                                        Text("5,000").tag(5000)
                                        Text("10,000").tag(10000)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 220)
                                }
                                .padding(.leading, 40)
                            }
                        }
                        
                        Divider()
                        
                        // Max Age Limit
                        VStack(spacing: 8) {
                            HStack {
                                Toggle("", isOn: $retentionMaxAgeEnabled)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                Text(L10n.t("storage.deleteOlder", "Delete items older than"))
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            
                            if retentionMaxAgeEnabled {
                                HStack {
                                    Text(L10n.t("storage.maxAge", "Max age:"))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Picker("", selection: $retentionMaxAgeDays) {
                                        Text(L10n.t("storage.days7", "7 days")).tag(7)
                                        Text(L10n.t("storage.days30", "30 days")).tag(30)
                                        Text(L10n.t("storage.days90", "90 days")).tag(90)
                                        Text(L10n.t("storage.year1", "1 year")).tag(365)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 220)
                                }
                                .padding(.leading, 40)
                            }
                        }
                    }
                }
                
                // Large File Storage Card
                SettingsCard(title: L10n.t("storage.largeFileStorage", "Large File Storage"), icon: "doc.badge.gearshape") {
                    VStack(spacing: 16) {
                        // Toggle row with left-aligned switch
                        VStack(spacing: 8) {
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { storageSettings.enableExternalStorage },
                                    set: { newValue in
                                        if newValue != storageSettings.enableExternalStorage {
                                            migrationAction = newValue ? .enableExternal : .disableExternal
                                            showMigrationDialog = true
                                        }
                                    }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                
                                Text(L10n.t("storage.storeExternal", "Store large files externally"))
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            
                            HStack {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(L10n.t("storage.externalHint", "Improves database performance for large content"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        
                        if storageSettings.enableExternalStorage {
                            Divider()
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text(L10n.t("storage.threshold", "Threshold"))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(storageSettings.thresholdDescription)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                }
                                
                                Slider(
                                    value: Binding(
                                        get: { Double(storageSettings.largeFileThreshold) },
                                        set: { storageSettings.largeFileThreshold = Int($0) }
                                    ),
                                    in: 102400...10_485_760,
                                    step: 102400
                                )
                                .accentColor(.accentColor)
                                
                                HStack {
                                    Text("100 KB")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("10 MB")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.leading, 40)
                        }
                    }
                }
                
                // Danger Zone
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.red)
                        Text(L10n.t("storage.dangerZone", "Danger Zone"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    
                    Button(action: { showClearConfirmation = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text(L10n.t("storage.clearAllHistory", "Clear All History"))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .alert(L10n.t("settings.clearAllHistory", "Clear All History?"), isPresented: $showClearConfirmation) {
                        Button(L10n.t("settings.cancel", "Cancel"), role: .cancel) {}
                        Button(L10n.t("storage.clear", "Clear"), role: .destructive) {
                            ClipboardStore().clearAll()
                            clipboardMonitor.reloadFromDatabase()
                        }
                    } message: {
                        Text(L10n.t("storage.clearWarning", "This will permanently delete all clipboard history. This cannot be undone."))
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showMigrationDialog) {
            MigrationDialogView(
                action: migrationAction,
                onConfirm: { migrate in
                    handleMigration(action: migrationAction, shouldMigrate: migrate)
                    showMigrationDialog = false
                },
                onCancel: {
                    showMigrationDialog = false
                }
            )
        }
    }
    
    private func handleMigration(action: MigrationAction, shouldMigrate: Bool) {
        let store = ClipboardStore()
        
        switch action {
        case .enableExternal:
            storageSettings.enableExternalStorage = true
            if shouldMigrate {
                let count = store.migrateLargeToExternal()
                print("Migrated \(count) items to external storage")
            }
            
        case .disableExternal:
            if shouldMigrate {
                let count = store.migrateExternalToDatabase()
                print("Migrated \(count) items to database")
            }
            storageSettings.enableExternalStorage = false
            
        case .none:
            break
        }
        
        clipboardMonitor.reloadFromDatabase()
    }
}

// MARK: - Stat Item
struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Migration Dialog View
struct MigrationDialogView: View {
    let action: StorageSettingsView.MigrationAction
    let onConfirm: (Bool) -> Void
    let onCancel: () -> Void
    
    @State private var shouldMigrate = true
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: action == .enableExternal ? "arrow.right.doc.on.clipboard" : "arrow.left.doc.on.clipboard")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
            }
            
            // Title
            Text(action == .enableExternal ? L10n.t("storage.enableExternalTitle", "Enable External Storage?") : L10n.t("storage.disableExternalTitle", "Disable External Storage?"))
                .font(.system(size: 18, weight: .semibold))
            
            // Description
            VStack(spacing: 16) {
                if action == .enableExternal {
                    Text(L10n.t("storage.enableExternalDesc", "Large files exceeding the threshold will be stored separately to improve database performance."))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    
                    Toggle(L10n.t("storage.migrateExisting", "Migrate existing large items"), isOn: $shouldMigrate)
                        .font(.system(size: 13))
                } else {
                    Text(L10n.t("storage.disableExternalDesc", "Choose how to handle files currently stored externally:"))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    
                    Toggle(L10n.t("storage.moveBack", "Move files back to database"), isOn: $shouldMigrate)
                        .font(.system(size: 13))
                    
                    if !shouldMigrate {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(L10n.t("storage.orphanWarning", "External files will be orphaned"))
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text(L10n.t("settings.cancel", "Cancel"))
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: { onConfirm(shouldMigrate) }) {
                    Text(L10n.t("storage.confirm", "Confirm"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(32)
        .frame(width: 400)
    }
}

#Preview {
    StorageSettingsView()
}

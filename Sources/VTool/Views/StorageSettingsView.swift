import SwiftUI

// MARK: - Storage Settings View
struct StorageSettingsView: View {
    @ObservedObject private var storageSettings = StorageSettings.shared
    @ObservedObject private var clipboardMonitor = ClipboardMonitor.shared
    
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
                SettingsCard(title: "Database Statistics", icon: "chart.bar.fill") {
                    HStack(spacing: 24) {
                        StatItem(
                            value: "\(clipboardMonitor.itemCount)",
                            label: "Items",
                            icon: "doc.on.doc"
                        )
                        
                        Divider()
                            .frame(height: 40)
                        
                        StatItem(
                            value: ByteCountFormatter.string(fromByteCount: clipboardMonitor.totalSize, countStyle: .file),
                            label: "Total Size",
                            icon: "internaldrive"
                        )
                        
                        Divider()
                            .frame(height: 40)
                        
                        StatItem(
                            value: "\(clipboardMonitor.externalFileCount)",
                            label: "External",
                            icon: "folder"
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // History Limit Card (Auto-Cleanup)
                SettingsCard(title: "History Limit", icon: "clock.arrow.circlepath") {
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("Automatically delete old items to save storage. Disabled by default.")
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
                                Text("Limit total saved items")
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            
                            if retentionMaxItemsEnabled {
                                HStack {
                                    Text("Keep at most:")
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
                                Text("Delete items older than")
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            
                            if retentionMaxAgeEnabled {
                                HStack {
                                    Text("Max age:")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Picker("", selection: $retentionMaxAgeDays) {
                                        Text("7 days").tag(7)
                                        Text("30 days").tag(30)
                                        Text("90 days").tag(90)
                                        Text("1 year").tag(365)
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
                SettingsCard(title: "Large File Storage", icon: "doc.badge.gearshape") {
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
                                
                                Text("Store large files externally")
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            
                            HStack {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("Improves database performance for large content")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        
                        if storageSettings.enableExternalStorage {
                            Divider()
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Threshold")
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
                        Text("Danger Zone")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    
                    Button(action: { showClearConfirmation = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All History")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .alert("Clear All History?", isPresented: $showClearConfirmation) {
                        Button("Cancel", role: .cancel) {}
                        Button("Clear", role: .destructive) {
                            ClipboardStore().clearAll()
                            clipboardMonitor.reloadFromDatabase()
                        }
                    } message: {
                        Text("This will permanently delete all clipboard history. This cannot be undone.")
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
            Text(action == .enableExternal ? "Enable External Storage?" : "Disable External Storage?")
                .font(.system(size: 18, weight: .semibold))
            
            // Description
            VStack(spacing: 16) {
                if action == .enableExternal {
                    Text("Large files exceeding the threshold will be stored separately to improve database performance.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    
                    Toggle("Migrate existing large items", isOn: $shouldMigrate)
                        .font(.system(size: 13))
                } else {
                    Text("Choose how to handle files currently stored externally:")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    
                    Toggle("Move files back to database", isOn: $shouldMigrate)
                        .font(.system(size: 13))
                    
                    if !shouldMigrate {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("External files will be orphaned")
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
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: { onConfirm(shouldMigrate) }) {
                    Text("Confirm")
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

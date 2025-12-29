import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

struct PreferencesView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)
            
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(1)
            
            HotkeySettingsView()
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }
                .tag(2)
            
            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
                .tag(3)
            
            StorageSettingsView()
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }
                .tag(4)
            
            SyncSettingsView()
                .tabItem {
                    Label("Sync", systemImage: "icloud")
                }
                .tag(5)
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(6)
        }
        .frame(width: 550, height: 450)
        .preferredColorScheme(themeManager.colorScheme)
    }
}

// MARK: - Popup Position
enum PopupPosition: String, CaseIterable {
    case menuBar = "menuBar"
    case center = "center"
    case mouseCursor = "mouseCursor"
    
    var displayName: String {
        switch self {
        case .menuBar: return "Menu Bar"
        case .center: return "Screen Center"
        case .mouseCursor: return "Mouse Cursor"
        }
    }
    
    var description: String {
        switch self {
        case .menuBar: return "Window appears below menu bar icon"
        case .center: return "Window appears at screen center"
        case .mouseCursor: return "Window appears at mouse cursor"
        }
    }
}

// MARK: - Menu Bar Fallback (when icon is hidden by Bartender etc)
enum MenuBarFallback: String, CaseIterable {
    case topCenter = "topCenter"
    case screenCenter = "screenCenter"
    
    var displayName: String {
        switch self {
        case .topCenter: return "Top Center"
        case .screenCenter: return "Screen Center"
        }
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @AppStorage("historyLimit") private var historyLimit = 1000
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("popupPosition") private var popupPosition = PopupPosition.menuBar.rawValue
    @AppStorage("menuBarFallback") private var menuBarFallback = MenuBarFallback.topCenter.rawValue
    
    // Retention settings (defaults off)
    @AppStorage("retentionMaxItemsEnabled") private var retentionMaxItemsEnabled = false
    @AppStorage("retentionMaxItems") private var retentionMaxItems = 1000
    @AppStorage("retentionMaxAgeEnabled") private var retentionMaxAgeEnabled = false
    @AppStorage("retentionMaxAgeDays") private var retentionMaxAgeDays = 30
    
    // Clear history confirmation
    @State private var showClearHistoryAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Startup Card
                SettingsCard(title: "Startup", icon: "power") {
                    VStack(spacing: 12) {
                        HStack {
                            LaunchAtLogin.Toggle {
                                Text("Launch at login")
                                    .font(.system(size: 13))
                            }
                            Spacer()
                        }
                        
                        Divider()
                        
                        HStack {
                            Text("Show in Dock")
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $showInDock)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }
                
                // Popup Card
                SettingsCard(title: "Popup Window", icon: "macwindow") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Position")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $popupPosition) {
                                ForEach(PopupPosition.allCases, id: \.rawValue) { position in
                                    Text(position.displayName).tag(position.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 240)
                        }
                        
                        // Dynamic description based on selected position
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(PopupPosition(rawValue: popupPosition)?.description ?? "")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        // Fallback option for Menu Bar position (e.g., when using Bartender)
                        if popupPosition == PopupPosition.menuBar.rawValue {
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Fallback Position")
                                        .font(.system(size: 13))
                                    Text("When menu bar icon is hidden (e.g., by Bartender)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $menuBarFallback) {
                                    ForEach(MenuBarFallback.allCases, id: \.rawValue) { fallback in
                                        Text(fallback.displayName).tag(fallback.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }
                        }
                    }
                }
                
                // History Card
                SettingsCard(title: "History", icon: "clock") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("In-memory items")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $historyLimit) {
                                Text("100").tag(100)
                                Text("500").tag(500)
                                Text("1000").tag(1000)
                                Text("∞").tag(10000)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                        
                        Divider()
                        
                        Button(action: {
                            showClearHistoryAlert = true
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear History")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .alert("Clear All History?", isPresented: $showClearHistoryAlert) {
                            Button("Cancel", role: .cancel) {}
                            Button("Clear All", role: .destructive) {
                                ClipboardMonitor.shared.clearHistory()
                            }
                        } message: {
                            Text("This will permanently delete ALL clipboard history from the database, including favorites. This action cannot be undone.")
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Appearance Settings (NEW)
struct AppearanceSettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var previewText = "The quick brown fox jumps over the lazy dog."
    
    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance:", selection: $themeManager.themeMode) {
                    ForEach(ThemeManager.ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: themeManager.themeMode) { _ in
                    themeManager.updateColorScheme()
                }
                
                Text("Choose System to automatically match your macOS appearance.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Font Size") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("List font size:")
                        Spacer()
                        Text("\(Int(themeManager.fontSize)) pt")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $themeManager.fontSize, in: 10...18, step: 1) {
                        Text("List Font Size")
                    }
                    
                    HStack {
                        Text("Preview font size:")
                        Spacer()
                        Text("\(Int(themeManager.previewFontSize)) pt")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $themeManager.previewFontSize, in: 11...24, step: 1) {
                        Text("Preview Font Size")
                    }
                }
            }
            
            Section("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("List item preview:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(previewText)
                                .font(.system(size: themeManager.fontSize))
                                .lineLimit(1)
                            Text("Preview App")
                                .font(.system(size: themeManager.fontSize - 2))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    Divider()
                    
                    Text("Content preview:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(previewText)
                        .font(.system(size: themeManager.previewFontSize, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
    }
}

// MARK: - Hotkey Settings
// Note: KeyboardShortcuts.Name extensions are defined in VToolApp.swift

struct HotkeySettingsView: View {
    @ObservedObject private var keyBindingManager = KeyBindingManager.shared
    @State private var recordingCommand: KeyBindingManager.Command? = nil
    @State private var showResetConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Global Hotkeys Card
                SettingsCard(title: "Global Hotkeys", icon: "globe") {
                    VStack(spacing: 12) {
                        GlobalHotkeyRow(
                            title: "Toggle Popup",
                            description: "Show/hide clipboard history",
                            shortcutName: .togglePopup,
                            defaultKey: "⌘⇧V"
                        )
                        
                        Divider()
                        
                        GlobalHotkeyRow(
                            title: "Paste Next",
                            description: "Paste next item in queue",
                            shortcutName: .pasteSequential,
                            defaultKey: "⌘⌥V"
                        )
                        
                        Text("Click recorder → Press new shortcut. Click ⌫ to clear.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                
                // VIM Keys Card
                SettingsCard(title: "VIM Mode Shortcuts", icon: "keyboard") {
                    VStack(spacing: 0) {
                        ForEach(Array(KeyBindingManager.Command.allCases.enumerated()), id: \.element.id) { index, command in
                            KeyBindingRow(
                                command: command,
                                binding: keyBindingManager.binding(for: command),
                                isRecording: recordingCommand == command,
                                isCustomized: keyBindingManager.bindings[command] != nil,
                                onTap: { recordingCommand = command },
                                onReset: { keyBindingManager.resetToDefault(command: command) }
                            )
                            
                            if index < KeyBindingManager.Command.allCases.count - 1 {
                                Divider()
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
                
                // Conflict Warning
                if let conflict = keyBindingManager.lastConflict {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("⚠️ \"\(conflict.command.rawValue)\" conflicts with \"\(conflict.conflictsWith.rawValue)\"")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Reset All Button
                Button(action: { showResetConfirmation = true }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset All to Defaults")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .alert("Reset All Shortcuts?", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        keyBindingManager.resetAllToDefaults()
                    }
                } message: {
                    Text("This will restore all shortcuts to their default values.")
                }
                
                // Reference Card
                SettingsCard(title: "Always Available", icon: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        ReferenceRow(keys: "↑ ↓", description: "Arrow keys for navigation")
                        ReferenceRow(keys: "1-9", description: "Quick select & paste")
                        ReferenceRow(keys: "⎋", description: "Exit current mode")
                    }
                }
            }
            .padding(20)
        }
        .background(KeyRecorderView(recordingCommand: $recordingCommand, keyBindingManager: keyBindingManager))
    }
}

// MARK: - Key Binding Row
struct KeyBindingRow: View {
    let command: KeyBindingManager.Command
    let binding: KeyBindingManager.KeyBinding
    let isRecording: Bool
    let isCustomized: Bool
    let onTap: () -> Void
    let onReset: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Text(command.rawValue)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: onTap) {
                HStack(spacing: 6) {
                    if isRecording {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                        Text("Press key...")
                            .foregroundColor(.orange)
                    } else {
                        Text(binding.displayString)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
                .frame(minWidth: 70)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isRecording ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.orange : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundColor(isCustomized ? .accentColor : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!isCustomized)
            .help(isCustomized ? "Reset to default" : "Using default")
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Reference Row
struct ReferenceRow: View {
    let keys: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 50, alignment: .leading)
            
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Settings Card
struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: () -> Content
    
    init(title: String, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            
            content()
                .padding(16)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(10)
        }
    }
}

// MARK: - Global Hotkey Row
struct GlobalHotkeyRow: View {
    let title: String
    let description: String
    let shortcutName: KeyboardShortcuts.Name
    let defaultKey: String
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            KeyboardShortcuts.Recorder("", name: shortcutName)
                .frame(width: 120)
            
            Button(action: {
                // Reset to default
                if shortcutName == .togglePopup {
                    KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .shift]), for: .togglePopup)
                } else if shortcutName == .pasteSequential {
                    KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .option]), for: .pasteSequential)
                }
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Reset to default: \(defaultKey)")
        }
    }
}

// MARK: - Key Recorder View
struct KeyRecorderView: NSViewRepresentable {
    @Binding var recordingCommand: KeyBindingManager.Command?
    let keyBindingManager: KeyBindingManager
    
    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onKeyDown = { event in
            guard let command = recordingCommand else { return false }
            
            // Escape cancels recording
            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    recordingCommand = nil
                }
                return true
            }
            
            let binding = KeyBindingManager.KeyBinding(
                key: KeyBindingManager.keyName(for: event.keyCode),
                keyCode: event.keyCode,
                requiresShift: event.modifierFlags.contains(.shift),
                requiresCommand: event.modifierFlags.contains(.command),
                requiresOption: event.modifierFlags.contains(.option),
                requiresControl: event.modifierFlags.contains(.control)
            )
            
            DispatchQueue.main.async {
                keyBindingManager.setBinding(binding, for: command)
                recordingCommand = nil
            }
            
            return true
        }
        return view
    }
    
    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {}
}

class KeyRecorderNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    private var localMonitor: Any?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let onKeyDown = self?.onKeyDown, onKeyDown(event) {
                return nil
            }
            return event
        }
    }
    
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

struct HotkeyRow: View {
    let key: String
    let action: String
    
    var body: some View {
        HStack {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .leading)
            
            Text(action)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Privacy Settings
struct PrivacySettingsView: View {
    @StateObject private var privacyFilter = PrivacyFilter()
    @State private var newAppBundleId = ""
    @State private var newKeyword = ""
    
    var body: some View {
        Form {
            Section("Excluded Apps") {
                Text("Content from these apps will not be recorded:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(privacyFilter.rules.filter { $0.appBundleId != nil }) { rule in
                    HStack {
                        Text(rule.appBundleId ?? "")
                        Spacer()
                        Button(action: { privacyFilter.removeRule(id: rule.id) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                HStack {
                    TextField("Bundle ID (e.g., com.example.app)", text: $newAppBundleId)
                    Button("Add") {
                        if !newAppBundleId.isEmpty {
                            privacyFilter.addRule(PrivacyRule(appBundleId: newAppBundleId))
                            newAppBundleId = ""
                        }
                    }
                    .disabled(newAppBundleId.isEmpty)
                }
            }
            
            Section("Excluded Keywords") {
                Text("Content containing these keywords will not be recorded:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(privacyFilter.rules.filter { $0.keyword != nil }) { rule in
                    HStack {
                        Text(rule.keyword ?? "")
                        Spacer()
                        Button(action: { privacyFilter.removeRule(id: rule.id) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                HStack {
                    TextField("Keyword", text: $newKeyword)
                    Button("Add") {
                        if !newKeyword.isEmpty {
                            privacyFilter.addRule(PrivacyRule(keyword: newKeyword))
                            newKeyword = ""
                        }
                    }
                    .disabled(newKeyword.isEmpty)
                }
            }
        }
        .padding()
    }
}

// MARK: - Sync Settings
struct SyncSettingsView: View {
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable iCloud Sync", isOn: $iCloudSyncEnabled)
                
                Text("Sync your clipboard history across all your Mac devices.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if iCloudSyncEnabled {
                Section("Sync Status") {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected to iCloud")
                    }
                    
                    Button("Sync Now") {
                        // Trigger manual sync
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("VTool")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("A powerful clipboard manager for macOS with VIM-style navigation.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("Made with ❤️")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    PreferencesView()
}

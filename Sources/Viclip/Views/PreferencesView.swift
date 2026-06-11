import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

struct PreferencesView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = AppLanguageManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label(L10n.t("settings.tab.general", "General"), systemImage: "gear")
                }
                .tag(0)
            
            AppearanceSettingsView()
                .tabItem {
                    Label(L10n.t("settings.tab.appearance", "Appearance"), systemImage: "paintbrush")
                }
                .tag(1)
            
            HotkeySettingsView()
                .tabItem {
                    Label(L10n.t("settings.tab.hotkeys", "Hotkeys"), systemImage: "keyboard")
                }
                .tag(2)
            
            PrivacySettingsView()
                .tabItem {
                    Label(L10n.t("settings.tab.privacy", "Privacy"), systemImage: "hand.raised")
                }
                .tag(3)
            
            StorageSettingsView()
                .tabItem {
                    Label(L10n.t("settings.tab.storage", "Storage"), systemImage: "internaldrive")
                }
                .tag(4)
            
            SyncSettingsView()
                .tabItem {
                    Label(L10n.t("settings.tab.sync", "Sync"), systemImage: "icloud")
                }
                .tag(5)
            
            AboutView()
                .tabItem {
                    Label(L10n.t("settings.tab.about", "About"), systemImage: "info.circle")
                }
                .tag(6)
        }
        .frame(minWidth: 550, minHeight: 450)
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
        case .menuBar: return L10n.t("popupPosition.menuBar", "Menu Bar")
        case .center: return L10n.t("popupPosition.center", "Screen Center")
        case .mouseCursor: return L10n.t("popupPosition.mouseCursor", "Mouse Cursor")
        }
    }
    
    var description: String {
        switch self {
        case .menuBar: return L10n.t("popupPosition.menuBarDesc", "Window appears below menu bar icon")
        case .center: return L10n.t("popupPosition.centerDesc", "Window appears at screen center")
        case .mouseCursor: return L10n.t("popupPosition.mouseCursorDesc", "Window appears at mouse cursor")
        }
    }
}

// MARK: - Menu Bar Fallback (when icon is hidden by Bartender etc)
enum MenuBarFallback: String, CaseIterable {
    case topCenter = "topCenter"
    case screenCenter = "screenCenter"
    
    var displayName: String {
        switch self {
        case .topCenter: return L10n.t("menuBarFallback.topCenter", "Top Center")
        case .screenCenter: return L10n.t("menuBarFallback.screenCenter", "Screen Center")
        }
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @ObservedObject private var languageManager = AppLanguageManager.shared
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
                SettingsCard(title: L10n.t("settings.language", "Language"), icon: "globe") {
                    VStack(spacing: 12) {
                        HStack {
                            Text(L10n.t("settings.language", "Language"))
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $languageManager.selectedLanguage) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 260)
                        }

                        HStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(L10n.t("settings.languageHint", "Applies immediately to Viclip windows."))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }

                // Startup Card
                SettingsCard(title: L10n.t("settings.startup", "Startup"), icon: "power") {
                    VStack(spacing: 12) {
                        HStack {
                            LaunchAtLogin.Toggle {
                                Text(L10n.t("settings.launchAtLogin", "Launch at login"))
                                    .font(.system(size: 13))
                            }
                            Spacer()
                        }
                        
                        Divider()
                        
                        HStack {
                            Text(L10n.t("settings.showInDock", "Show in Dock"))
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $showInDock)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }
                
                // Popup Card
                SettingsCard(title: L10n.t("settings.popupWindow", "Popup Window"), icon: "macwindow") {
                    VStack(spacing: 12) {
                        HStack {
                            Text(L10n.t("settings.position", "Position"))
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
                                    Text(L10n.t("settings.fallbackPosition", "Fallback Position"))
                                        .font(.system(size: 13))
                                    Text(L10n.t("settings.fallbackHint", "When menu bar icon is hidden (e.g., by Bartender)"))
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
                SettingsCard(title: L10n.t("settings.history", "History"), icon: "clock") {
                    VStack(spacing: 12) {
                        HStack {
                            Text(L10n.t("settings.inMemoryItems", "In-memory items"))
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
                                Text(L10n.t("settings.clearHistory", "Clear History"))
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .alert(L10n.t("settings.clearAllHistory", "Clear All History?"), isPresented: $showClearHistoryAlert) {
                            Button(L10n.t("settings.cancel", "Cancel"), role: .cancel) {}
                            Button(L10n.t("settings.clearAll", "Clear All"), role: .destructive) {
                                ClipboardMonitor.shared.clearHistory()
                            }
                        } message: {
                            Text(L10n.t("settings.clearHistoryWarning", "This will permanently delete ALL clipboard history from the database, including favorites. This action cannot be undone."))
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
            Section(L10n.t("settings.theme", "Theme")) {
                Picker("Appearance:", selection: $themeManager.themeMode) {
                    ForEach(ThemeManager.ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: themeManager.themeMode) { _ in
                    themeManager.updateColorScheme()
                }
                
                Text(L10n.t("settings.themeHint", "Choose System to automatically match your macOS appearance."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(L10n.t("settings.fontSize", "Font Size")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.t("settings.listFontSize", "List font size:"))
                        Spacer()
                        Text("\(Int(themeManager.fontSize)) pt")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $themeManager.fontSize, in: 10...18, step: 1) {
                        Text(L10n.t("settings.listFontSizeControl", "List Font Size"))
                    }
                    
                    HStack {
                        Text(L10n.t("settings.previewFontSize", "Preview font size:"))
                        Spacer()
                        Text("\(Int(themeManager.previewFontSize)) pt")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $themeManager.previewFontSize, in: 11...24, step: 1) {
                        Text(L10n.t("settings.previewFontSizeControl", "Preview Font Size"))
                    }
                }
            }
            
            Section(L10n.t("popup.preview", "Preview")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("settings.listItemPreview", "List item preview:"))
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
                            Text(L10n.t("settings.previewApp", "Preview App"))
                                .font(.system(size: themeManager.fontSize - 2))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    Divider()
                    
                    Text(L10n.t("settings.contentPreview", "Content preview:"))
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
                SettingsCard(title: L10n.t("settings.globalHotkeys", "Global Hotkeys"), icon: "globe") {
                    VStack(spacing: 12) {
                        GlobalHotkeyRow(
                            title: L10n.t("settings.togglePopup", "Toggle Popup"),
                            description: L10n.t("settings.togglePopupDesc", "Show/hide clipboard history"),
                            shortcutName: .togglePopup,
                            defaultKey: "⌘⇧V"
                        )
                        
                        Divider()
                        
                        GlobalHotkeyRow(
                            title: L10n.t("settings.pasteNext", "Paste Next"),
                            description: L10n.t("settings.pasteNextDesc", "Paste next item in queue"),
                            shortcutName: .pasteSequential,
                            defaultKey: "⌘⌥V"
                        )
                        
                        Text(L10n.t("settings.recorderHint", "Click recorder → Press new shortcut. Click ⌫ to clear."))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                
                // VIM Keys Card
                SettingsCard(title: L10n.t("settings.vimShortcuts", "VIM Mode Shortcuts"), icon: "keyboard") {
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
                        Text("⚠️ \"\(conflict.command.localizedTitle)\" \(L10n.t("settings.conflictsWith", "conflicts with")) \"\(conflict.conflictsWith.localizedTitle)\"")
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
                        Text(L10n.t("settings.resetAllDefaults", "Reset All to Defaults"))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .alert(L10n.t("settings.resetAllShortcuts", "Reset All Shortcuts?"), isPresented: $showResetConfirmation) {
                    Button(L10n.t("settings.cancel", "Cancel"), role: .cancel) {}
                    Button(L10n.t("settings.reset", "Reset"), role: .destructive) {
                        keyBindingManager.resetAllToDefaults()
                    }
                } message: {
                    Text(L10n.t("settings.resetShortcutsWarning", "This will restore all shortcuts to their default values."))
                }
                
                // Reference Card
                SettingsCard(title: L10n.t("settings.alwaysAvailable", "Always Available"), icon: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        ReferenceRow(keys: "↑ ↓", description: L10n.t("settings.arrowNav", "Arrow keys for navigation"))
                        ReferenceRow(keys: "1-9", description: L10n.t("settings.quickSelectPaste", "Quick select & paste"))
                        ReferenceRow(keys: "⎋", description: L10n.t("settings.exitCurrentMode", "Exit current mode"))
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
            Text(command.localizedTitle)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: onTap) {
                HStack(spacing: 6) {
                    if isRecording {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                        Text(L10n.t("settings.pressKey", "Press key..."))
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
            .help(isCustomized ? L10n.t("settings.resetDefault", "Reset to default") : L10n.t("settings.usingDefault", "Using default"))
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
            .help("\(L10n.t("settings.resetDefault", "Reset to default")): \(defaultKey)")
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
            Section(L10n.t("settings.excludedApps", "Excluded Apps")) {
                Text(L10n.t("settings.excludedAppsHint", "Content from these apps will not be recorded:"))
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
                    TextField(L10n.t("settings.bundleIdPlaceholder", "Bundle ID (e.g., com.example.app)"), text: $newAppBundleId)
                    Button(L10n.t("settings.add", "Add")) {
                        if !newAppBundleId.isEmpty {
                            privacyFilter.addRule(PrivacyRule(appBundleId: newAppBundleId))
                            newAppBundleId = ""
                        }
                    }
                    .disabled(newAppBundleId.isEmpty)
                }
            }
            
            Section(L10n.t("settings.excludedKeywords", "Excluded Keywords")) {
                Text(L10n.t("settings.excludedKeywordsHint", "Content containing these keywords will not be recorded:"))
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
                    TextField(L10n.t("settings.keyword", "Keyword"), text: $newKeyword)
                    Button(L10n.t("settings.add", "Add")) {
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
                Toggle(L10n.t("settings.enableICloudSync", "Enable iCloud Sync"), isOn: $iCloudSyncEnabled)
                
                Text(L10n.t("settings.iCloudHint", "Sync your clipboard history across all your Mac devices."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if iCloudSyncEnabled {
                Section(L10n.t("settings.syncStatus", "Sync Status")) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(L10n.t("settings.connectedICloud", "Connected to iCloud"))
                    }
                    
                    Button(L10n.t("settings.syncNow", "Sync Now")) {
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
    // Try to load app icon from various sources
    private var appIconImage: NSImage? {
        // 1. Try bundle's AppIcon
        if let icon = NSImage(named: "AppIcon"), icon.size.width > 0 {
            return icon
        }
        
        // 2. Try to load from Resources in bundle
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            return icon
        }
        
        // 3. For development: try to load from source directory
        let possiblePaths = [
            "Sources/Viclip/Resources/AppIcon.icns",
            "../Sources/Viclip/Resources/AppIcon.icns",
            "logo.png",
            "../logo.png"
        ]
        for path in possiblePaths {
            if let icon = NSImage(contentsOfFile: path), icon.size.width > 0 {
                return icon
            }
        }
        
        return nil
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Use app icon
            if let icon = appIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 128, height: 128)
            } else {
                // Fallback to SF Symbol if icon not found
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
            }
            
            Text("Viclip")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(L10n.t("settings.version", "Version 0.01"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(L10n.t("settings.aboutDescription", "A powerful clipboard manager for macOS with VIM-style navigation."))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Link("GitHub", destination: URL(string: "https://github.com/seongminhwan/viclip")!)
                .font(.caption)
            
            Text(L10n.t("settings.madeWith", "Made with ❤️"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    PreferencesView()
}

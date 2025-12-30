import SwiftUI
import KeyboardShortcuts
import os.log

// MARK: - Global Shortcut Definitions
extension KeyboardShortcuts.Name {
    static let togglePopup = Self("togglePopup")
    static let pasteSequential = Self("pasteSequential")
}

@main
struct VToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Set default shortcuts if not already set
        if KeyboardShortcuts.getShortcut(for: .togglePopup) == nil {
            KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .shift]), for: .togglePopup)
        }
        if KeyboardShortcuts.getShortcut(for: .pasteSequential) == nil {
            KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .option]), for: .pasteSequential)
        }
    }
    
    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var clipboardMonitor: ClipboardMonitor!
    private var eventMonitor: Any?
    private var isWindowVisible = false
    
    // Window dimensions
    private let baseWindowWidth: CGFloat = 700
    private let windowHeight: CGFloat = 500
    private let tagPanelWidth: CGFloat = 200
    
    // Store the previously active application (tracked via NSWorkspace notification)
    private var previousApp: NSRunningApplication?
    
    // Observer for app activation events
    private var appActivationObserver: NSObjectProtocol?
    
    // Tag panel state observer
    private var tagPanelObserver: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // Initialize clipboard monitor
        clipboardMonitor = ClipboardMonitor.shared
        
        // Run retention cleanup on startup (async to not block launch)
        DispatchQueue.global(qos: .background).async {
            ClipboardStore().runRetentionCleanup()
        }
        
        // Check permissions on launch (with slight delay for better UX)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            PermissionManager.shared.checkAndRequestPermissions()
        }
        
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "VTool")
            button.action = #selector(toggleWindow)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Setup global hotkeys using KeyboardShortcuts
        setupKeyboardShortcuts()
        
        // Monitor for clicks outside window to close it
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let window = self.mainWindow, window.isVisible else { return }
            
            // Check if click is outside the window
            if !window.frame.contains(NSEvent.mouseLocation) {
                self.hideWindow()
            }
        }
        
        // Observe tag panel state changes
        tagPanelObserver = NotificationCenter.default.addObserver(
            forName: .tagPanelStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let isOpen = notification.userInfo?["isOpen"] as? Bool else { return }
            self?.adjustWindowForTagPanel(isOpen: isOpen)
        }
        
        // Close popup when window loses focus (becomes not key)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, 
                  let window = notification.object as? NSWindow,
                  window === self.mainWindow,
                  self.isWindowVisible else { return }
            // Delay slightly to allow for multi-window interactions
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.isWindowVisible && !(self.mainWindow?.isKeyWindow ?? false) {
                    self.hideWindow()
                }
            }
        }
        
        // Monitor app activation to reliably track the previous non-Viclip app
        // This is more reliable than checking frontmostApplication in showWindow()
        let myBundleId = Bundle.main.bundleIdentifier
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != myBundleId else { return }
            // Only update previousApp if it's a normal app (not Viclip)
            self?.previousApp = app
        }
        
        // Hide dock icon for menu bar app
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let observer = tagPanelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    private func setupKeyboardShortcuts() {
        // Toggle popup shortcut
        KeyboardShortcuts.onKeyDown(for: .togglePopup) { [weak self] in
            self?.toggleWindow()
        }
        
        // Paste sequential shortcut
        KeyboardShortcuts.onKeyDown(for: .pasteSequential) { [weak self] in
            self?.pasteNextInQueue()
        }
    }
    
    // MARK: - Window Management
    
    private func createWindow() -> NSWindow {
        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: baseWindowWidth, height: windowHeight),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // Set content view with rounded corners
        let hostingView = NSHostingView(rootView: 
            ThemedPopupView()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true
        
        window.contentView = hostingView
        
        return window
    }
    
    @objc func toggleWindow() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            if isWindowVisible {
                hideWindow()
            } else {
                showWindow()
            }
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        // Show Main Window
        let showItem = NSMenuItem(title: "Show Main Window", action: #selector(showWindowFromMenu), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.frame.height), in: button)
        }
    }
    
    @objc func showWindowFromMenu() {
        showWindow()
    }
    
    @objc func openSettings() {
        // Create settings window if needed
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Viclip Settings"
            window.center()
            window.contentView = NSHostingView(rootView: PreferencesView())
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func showWindow() {
        // previousApp is now tracked via NSWorkspace.didActivateApplicationNotification
        // No need to manually track it here
        
        // Create window if needed
        if mainWindow == nil {
            mainWindow = createWindow()
        }
        
        guard let window = mainWindow, let screen = NSScreen.main else { return }
        
        // Position window based on settings
        let positionSetting = UserDefaults.standard.string(forKey: "popupPosition") ?? "center"
        let fallbackSetting = UserDefaults.standard.string(forKey: "menuBarFallback") ?? "topCenter"
        let screenFrame = screen.visibleFrame
        
        var windowFrame = window.frame
        
        switch positionSetting {
        case "menuBar":
            // Try to position below menu bar item
            var usedMenuBarPosition = false
            if let button = statusItem.button,
               let buttonWindow = button.window,
               buttonWindow.isVisible,
               button.frame.width > 0,
               buttonWindow.frame.origin.x > 0 {
                let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
                if buttonRect.minX > 0 && buttonRect.minY > 0 {
                    windowFrame.origin.x = buttonRect.midX - windowFrame.width / 2
                    windowFrame.origin.y = buttonRect.minY - windowFrame.height - 5
                    usedMenuBarPosition = true
                }
            }
            
            // Fallback if menu bar position failed (e.g., hidden by Bartender)
            if !usedMenuBarPosition {
                if fallbackSetting == "topCenter" {
                    // Fixed position at top center of screen (below menu bar area)
                    windowFrame.origin.x = screenFrame.midX - windowFrame.width / 2
                    windowFrame.origin.y = screenFrame.maxY - windowFrame.height - 30  // 30px below top
                } else {
                    // Fallback to screen center
                    windowFrame.origin.x = screenFrame.midX - windowFrame.width / 2
                    windowFrame.origin.y = screenFrame.midY - windowFrame.height / 2 + 50
                }
            }
            
        case "mouseCursor":
            // Position near mouse cursor
            let mouseLocation = NSEvent.mouseLocation
            windowFrame.origin.x = mouseLocation.x - windowFrame.width / 2
            windowFrame.origin.y = mouseLocation.y - windowFrame.height - 20  // Below cursor
            
        default:  // "center"
            // Center on screen
            windowFrame.origin.x = screenFrame.midX - windowFrame.width / 2
            windowFrame.origin.y = screenFrame.midY - windowFrame.height / 2 + 50
        }
        
        // Ensure window stays within screen bounds
        windowFrame.origin.x = max(screenFrame.minX + 10, min(windowFrame.origin.x, screenFrame.maxX - windowFrame.width - 10))
        windowFrame.origin.y = max(screenFrame.minY + 10, min(windowFrame.origin.y, screenFrame.maxY - windowFrame.height - 10))
        
        window.setFrame(windowFrame, display: false)
        
        // Animate in
        window.alphaValue = 0
        window.setFrame(
            NSRect(
                x: windowFrame.origin.x,
                y: windowFrame.origin.y - 10,
                width: windowFrame.width,
                height: windowFrame.height
            ),
            display: false
        )
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(windowFrame, display: true)
        }
        
        isWindowVisible = true
        
        // Post notification to focus search
        NotificationCenter.default.post(name: .focusSearch, object: nil)
    }
    
    private func hideWindow() {
        guard let window = mainWindow else { return }
        
        let currentFrame = window.frame
        let targetFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y - 10,
            width: currentFrame.width,
            height: currentFrame.height
        )
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            window.animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.isWindowVisible = false
        })
    }
    
    private func adjustWindowForTagPanel(isOpen: Bool) {
        guard let window = mainWindow, isWindowVisible else { return }
        
        var newFrame = window.frame
        
        if isOpen {
            // Expand window width and shift left
            newFrame.size.width = baseWindowWidth + tagPanelWidth
            newFrame.origin.x -= tagPanelWidth / 2
        } else {
            // Shrink window width and shift right
            newFrame.size.width = baseWindowWidth
            newFrame.origin.x += tagPanelWidth / 2
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }
    
    // Called by PreviewWindow to reopen window after closing preview
    func showMainPopover() {
        if !isWindowVisible {
            showWindow()
        }
    }
    
    func pasteNextInQueue() {
        _ = SequentialPaster.shared.pasteNext()
    }
    
    /// Close the popup without pasting (for ESC key)
    func closePopup() {
        hideWindow()
    }
    
    func closePopoverAndPaste() {
        // Close the window first
        hideWindow()
        
        // Activate the previous application and paste
        // Keep delay minimal for responsive UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            // Try to activate the previous app
            var appToActivate = self.previousApp
            
            // If no previousApp, try to find the last non-Viclip app
            if appToActivate == nil {
                let myBundleId = Bundle.main.bundleIdentifier
                appToActivate = NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != myBundleId }
                    .first
            }
            
            appToActivate?.activate(options: [.activateIgnoringOtherApps])
            
            // Wait for the app to activate, then simulate paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.simulatePaste()
            }
        }
    }
    
    private func simulatePaste() {
        // Use AppleScript to simulate Cmd+V - this provides better compatibility but requires permissions
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            
            if let error = error {
                let errorNumber = error["NSAppleScriptErrorNumber"] as? Int ?? 0
                // -1743 = "Not authorized to send Apple events"
                // 1002 = "Not allowed to send keystrokes" (requires Accessibility)
                if errorNumber == -1743 || errorNumber == 1002 {
                    PermissionManager.shared.showPermissionRequiredNotification()
                }
            }
        }
    }
}

// MARK: - Keyable Window
/// Custom NSWindow subclass that can become key window even when borderless
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("focusSearch")
    static let tagPanelStateChanged = Notification.Name("tagPanelStateChanged")
}

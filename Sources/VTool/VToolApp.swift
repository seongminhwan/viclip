import SwiftUI
import KeyboardShortcuts

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
    private var clipboardMonitor: ClipboardMonitor!
    private var eventMonitor: Any?
    private var isWindowVisible = false
    
    // Window dimensions
    private let baseWindowWidth: CGFloat = 700
    private let windowHeight: CGFloat = 500
    private let tagPanelWidth: CGFloat = 200
    
    // Store the previously active application
    private var previousApp: NSRunningApplication?
    
    // Tag panel state observer
    private var tagPanelObserver: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // Initialize clipboard monitor
        clipboardMonitor = ClipboardMonitor.shared
        
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "VTool")
            button.action = #selector(toggleWindow)
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
        if isWindowVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }
    
    private func showWindow() {
        // Remember the currently active application before showing window
        previousApp = NSWorkspace.shared.frontmostApplication
        
        // Create window if needed
        if mainWindow == nil {
            mainWindow = createWindow()
        }
        
        guard let window = mainWindow, let screen = NSScreen.main else { return }
        
        // Position window
        let positionSetting = UserDefaults.standard.string(forKey: "popupPosition") ?? "center"
        let screenFrame = screen.visibleFrame
        
        var windowFrame = window.frame
        
        if positionSetting == "menuBar", let button = statusItem.button, let buttonWindow = button.window {
            // Position below menu bar item
            let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            windowFrame.origin.x = buttonRect.midX - windowFrame.width / 2
            windowFrame.origin.y = buttonRect.minY - windowFrame.height - 5
        } else {
            // Center on screen
            windowFrame.origin.x = screenFrame.midX - windowFrame.width / 2
            windowFrame.origin.y = screenFrame.midY - windowFrame.height / 2 + 50
        }
        
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            // Activate the previous app
            if let previousApp = self?.previousApp {
                previousApp.activate(options: [.activateIgnoringOtherApps])
            }
            
            // Wait a bit for the app to activate, then simulate paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.simulatePaste()
            }
        }
    }
    
    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Key down
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        
        // Key up
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
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

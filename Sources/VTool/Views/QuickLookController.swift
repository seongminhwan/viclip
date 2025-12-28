import AppKit
import Quartz

// MARK: - Quick Look Preview Controller
class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    
    private var previewItem: QLPreviewItem?
    private var isActive = false
    
    private override init() {
        super.init()
        
        // Observe when Quick Look panel closes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func showPreview(for filePath: String) {
        let url = URL(fileURLWithPath: filePath)
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("[QuickLook] File not found: \(filePath)")
            return
        }
        
        previewItem = url as QLPreviewItem
        isActive = true
        
        // Get or create panel
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            panel.delegate = self
            
            if panel.isVisible {
                panel.reloadData()
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
            
            panel.currentPreviewItemIndex = 0
        }
    }
    
    func close() {
        guard isActive else { return }
        isActive = false
        
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
        previewItem = nil
        
        // Reopen main popover immediately
        DispatchQueue.main.async {
            AppDelegate.shared?.showMainPopover()
        }
    }
    
    @objc private func panelDidClose(_ notification: Notification) {
        // Check if the closing window is the Quick Look panel
        if let window = notification.object as? NSWindow,
           window == QLPreviewPanel.shared(),
           isActive {
            isActive = false
            previewItem = nil
            
            // Reopen main popover immediately
            DispatchQueue.main.async {
                AppDelegate.shared?.showMainPopover()
            }
        }
    }
    
    // MARK: - QLPreviewPanelDataSource
    
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewItem != nil ? 1 : 0
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return previewItem
    }
    
    // MARK: - QLPreviewPanelDelegate
    
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Handle ESC key or 'v' key to close and reopen main window
        if event.type == .keyDown && (event.keyCode == 53 || event.keyCode == 9) {
            close()
            return true
        }
        return false
    }
}


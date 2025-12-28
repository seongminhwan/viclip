import SwiftUI
import AppKit

// MARK: - Preview Window Controller
class PreviewWindowController: NSObject, NSWindowDelegate {
    static let shared = PreviewWindowController()
    
    private var panel: NSPanel?
    private var eventMonitor: Any?
    
    private override init() {
        super.init()
    }
    
    func showPreview(for item: ClipboardItem) {
        // Clean up any existing state
        cleanup()
        
        // Calculate window size
        let size = calculateSize(for: item)
        
        // Get centered position
        let position = getCenteredPosition(size: size)
        
        // Create panel with correct position
        let windowRect = NSRect(x: position.x, y: position.y, width: size.width, height: size.height)
        panel = NSPanel(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel?.title = "Preview - ESC/v close, o open"
        panel?.isReleasedWhenClosed = false
        panel?.level = .floating
        panel?.delegate = self
        panel?.hidesOnDeactivate = false
        panel?.becomesKeyOnlyIfNeeded = true
        
        // Create content directly with NSImageView/NSTextView
        panel?.contentView = createContentView(for: item)
        
        // Show panel
        panel?.makeKeyAndOrderFront(nil)
        
        // Handle ESC/v key to close - store the monitor
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 || event.keyCode == 9 { // ESC or v
                self?.close()
                return nil
            }
            // o to open in external app
            if event.keyCode == 31 {
                self?.openInExternalApp(item)
                return nil
            }
            return event
        }
    }
    
    func close() {
        cleanup()
    }
    
    private func cleanup() {
        // Remove event monitor first
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        // Close panel
        panel?.close()
        panel = nil
        
        // Reopen main popover after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AppDelegate.shared?.showMainPopover()
        }
    }
    
    // NSWindowDelegate - handle window close
    func windowWillClose(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func createContentView(for item: ClipboardItem) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true
        
        switch item.content {
        case .image(let data):
            if let nsImage = NSImage(data: data) {
                let imageView = NSImageView()
                imageView.image = nsImage
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.translatesAutoresizingMaskIntoConstraints = false
                // Prevent image from expanding beyond container
                imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
                containerView.addSubview(imageView)
                
                // Info label
                let infoLabel = NSTextField(labelWithString: "\(Int(nsImage.size.width))×\(Int(nsImage.size.height)) | \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                infoLabel.font = NSFont.systemFont(ofSize: 11)
                infoLabel.textColor = .secondaryLabelColor
                infoLabel.alignment = .center
                infoLabel.translatesAutoresizingMaskIntoConstraints = false
                containerView.addSubview(infoLabel)
                
                NSLayoutConstraint.activate([
                    imageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
                    imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
                    imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
                    imageView.bottomAnchor.constraint(equalTo: infoLabel.topAnchor, constant: -8),
                    
                    infoLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
                    infoLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
                    infoLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
                    infoLabel.heightAnchor.constraint(equalToConstant: 16)
                ])
            }
            
        case .text(let text):
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            
            let textView = NSTextView()
            textView.string = text
            textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.isEditable = false
            textView.isSelectable = true
            textView.textContainerInset = NSSize(width: 10, height: 10)
            
            scrollView.documentView = textView
            containerView.addSubview(scrollView)
            
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            
        case .fileURL(let path):
            let stackView = NSStackView()
            stackView.orientation = .vertical
            stackView.alignment = .leading
            stackView.spacing = 8
            stackView.translatesAutoresizingMaskIntoConstraints = false
            
            let titleLabel = NSTextField(labelWithString: URL(fileURLWithPath: path).lastPathComponent)
            titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
            
            let pathLabel = NSTextField(labelWithString: path)
            pathLabel.font = NSFont.systemFont(ofSize: 11)
            pathLabel.textColor = .secondaryLabelColor
            
            stackView.addArrangedSubview(titleLabel)
            stackView.addArrangedSubview(pathLabel)
            
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                let sizeLabel = NSTextField(labelWithString: "Size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                sizeLabel.font = NSFont.systemFont(ofSize: 12)
                stackView.addArrangedSubview(sizeLabel)
            }
            
            containerView.addSubview(stackView)
            
            NSLayoutConstraint.activate([
                stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
                stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
                stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20)
            ])
            
        case .richText(let data):
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            
            let textView = NSTextView()
            if let attrString = NSAttributedString(rtf: data, documentAttributes: nil) {
                textView.textStorage?.setAttributedString(attrString)
            }
            textView.isEditable = false
            textView.isSelectable = true
            textView.textContainerInset = NSSize(width: 10, height: 10)
            
            scrollView.documentView = textView
            containerView.addSubview(scrollView)
            
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }
        
        return containerView
    }
    
    private func openInExternalApp(_ item: ClipboardItem) {
        switch item.content {
        case .image(let data):
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vtool_preview.png")
            try? data.write(to: tempURL)
            NSWorkspace.shared.open(tempURL)
            
        case .fileURL(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            
        case .text(let text):
            if text.hasPrefix("/") || text.hasPrefix("~") {
                let expandedPath = (text as NSString).expandingTildeInPath
                if FileManager.default.fileExists(atPath: expandedPath) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: expandedPath))
                    return
                }
            }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vtool_preview.txt")
            try? text.write(to: tempURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempURL)
            
        case .richText(let data):
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vtool_preview.rtf")
            try? data.write(to: tempURL)
            NSWorkspace.shared.open(tempURL)
        }
        
        close()
    }
    
    private func calculateSize(for item: ClipboardItem) -> NSSize {
        // Main popover window size
        let mainWindowWidth: CGFloat = 700
        let mainWindowHeight: CGFloat = 500
        
        // Preview window size limits
        let minWidth = mainWindowWidth * 0.8   // 560
        let maxWidth = mainWindowWidth * 1.5   // 1050
        let minHeight = mainWindowHeight * 0.8  // 400
        let maxHeight = mainWindowHeight * 1.5  // 750
        
        switch item.content {
        case .image(let data):
            if let nsImage = NSImage(data: data) {
                // Get actual pixel dimensions
                var pixelWidth = nsImage.size.width
                var pixelHeight = nsImage.size.height
                
                if let rep = nsImage.representations.first {
                    if rep.pixelsWide > 0 {
                        pixelWidth = CGFloat(rep.pixelsWide)
                    }
                    if rep.pixelsHigh > 0 {
                        pixelHeight = CGFloat(rep.pixelsHigh)
                    }
                }
                
                // Scale factor for Retina
                let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
                var width = pixelWidth / scaleFactor
                var height = pixelHeight / scaleFactor
                
                // Scale to fit within bounds
                if width > maxWidth {
                    let ratio = maxWidth / width
                    width = maxWidth
                    height *= ratio
                }
                if height > maxHeight {
                    let ratio = maxHeight / height
                    height = maxHeight
                    width *= ratio
                }
                
                // Ensure minimum size
                width = max(minWidth, width)
                height = max(minHeight, height)
                
                print("[Preview] Image: \(pixelWidth)x\(pixelHeight)px, scale: \(scaleFactor), window: \(width)x\(height)")
                return NSSize(width: width, height: height)
            }
            return NSSize(width: minWidth, height: minHeight)
            
        case .text(let text):
            let lines = text.components(separatedBy: .newlines).count
            var width: CGFloat = text.count > 500 ? mainWindowWidth * 1.0 : minWidth
            var height = CGFloat(lines * 18 + 80)
            
            width = max(minWidth, min(maxWidth, width))
            height = max(minHeight, min(maxHeight, height))
            return NSSize(width: width, height: height)
            
        case .fileURL:
            return NSSize(width: minWidth, height: minHeight)
            
        case .richText:
            return NSSize(width: mainWindowWidth, height: mainWindowHeight)
        }
    }
    
    // Get center position based on popover location (assumes center of screen for now)
    private func getCenteredPosition(size: NSSize) -> NSPoint {
        // Find the screen where mouse is
        let mouseLocation = NSEvent.mouseLocation
        var targetScreen = NSScreen.main ?? NSScreen.screens.first!
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                targetScreen = screen
                break
            }
        }
        
        let screenFrame = targetScreen.visibleFrame
        let x = screenFrame.origin.x + (screenFrame.width - size.width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - size.height) / 2
        return NSPoint(x: x, y: y)
    }
}

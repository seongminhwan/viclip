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
    
    // MARK: - OCR Actions
    
    @objc private func performOCR(_ sender: NSButton) {
        guard let data = objc_getAssociatedObject(sender, "imageData") as? Data,
              let resultView = objc_getAssociatedObject(sender, "resultView") as? NSScrollView,
              let textView = objc_getAssociatedObject(sender, "textView") as? NSTextView,
              let copyButton = objc_getAssociatedObject(sender, "copyButton") as? NSButton else {
            return
        }
        
        // Show loading state
        sender.title = "⏳ Processing..."
        sender.isEnabled = false
        
        Task {
            do {
                let text = try await OCRService.shared.recognizeText(from: data)
                
                await MainActor.run {
                    textView.string = text
                    resultView.isHidden = false
                    copyButton.isHidden = false
                    sender.title = "✅ Text Extracted"
                    
                    // Resize window to accommodate OCR result
                    if let window = self.panel {
                        var frame = window.frame
                        frame.size.height += 150
                        frame.origin.y -= 150
                        window.setFrame(frame, display: true, animate: true)
                    }
                }
            } catch {
                await MainActor.run {
                    textView.string = "Error: \(error.localizedDescription)"
                    resultView.isHidden = false
                    sender.title = "❌ OCR Failed"
                    sender.isEnabled = true
                }
            }
        }
    }
    
    @objc private func copyOCRResult(_ sender: NSButton) {
        guard let textView = objc_getAssociatedObject(sender, "textView") as? NSTextView else {
            return
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textView.string, forType: .string)
        
        // Visual feedback
        let originalTitle = sender.title
        sender.title = "✅ Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            sender.title = originalTitle
        }
    }
    
    private func createContentView(for item: ClipboardItem) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true
        
        switch item.content {
        case .image(let data):
            if let nsImage = NSImage(data: data) {
                // Main vertical stack
                let mainStack = NSStackView()
                mainStack.orientation = .vertical
                mainStack.spacing = 8
                mainStack.translatesAutoresizingMaskIntoConstraints = false
                containerView.addSubview(mainStack)
                
                // Image view
                let imageView = NSImageView()
                imageView.image = nsImage
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
                mainStack.addArrangedSubview(imageView)
                
                // Info and OCR button row
                let bottomRow = NSStackView()
                bottomRow.orientation = .horizontal
                bottomRow.spacing = 12
                bottomRow.alignment = .centerY
                
                // Info label
                let infoLabel = NSTextField(labelWithString: "\(Int(nsImage.size.width))×\(Int(nsImage.size.height)) | \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                infoLabel.font = NSFont.systemFont(ofSize: 11)
                infoLabel.textColor = .secondaryLabelColor
                bottomRow.addArrangedSubview(infoLabel)
                
                // Spacer
                let spacer = NSView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                bottomRow.addArrangedSubview(spacer)
                
                // OCR Button
                let ocrButton = NSButton(title: "📝 Extract Text (OCR)", target: nil, action: nil)
                ocrButton.bezelStyle = .rounded
                ocrButton.font = NSFont.systemFont(ofSize: 11)
                bottomRow.addArrangedSubview(ocrButton)
                
                mainStack.addArrangedSubview(bottomRow)
                
                // OCR Result area (hidden initially)
                let ocrResultView = NSScrollView()
                ocrResultView.hasVerticalScroller = true
                ocrResultView.isHidden = true
                ocrResultView.heightAnchor.constraint(equalToConstant: 120).isActive = true
                
                let ocrTextView = NSTextView()
                ocrTextView.isEditable = false
                ocrTextView.isSelectable = true
                ocrTextView.font = NSFont.systemFont(ofSize: 12)
                ocrTextView.textContainerInset = NSSize(width: 8, height: 8)
                ocrResultView.documentView = ocrTextView
                mainStack.addArrangedSubview(ocrResultView)
                
                // Copy OCR result button (hidden initially)
                let copyButton = NSButton(title: "📋 Copy Text", target: nil, action: nil)
                copyButton.bezelStyle = .rounded
                copyButton.font = NSFont.systemFont(ofSize: 11)
                copyButton.isHidden = true
                mainStack.addArrangedSubview(copyButton)
                
                // OCR button action
                ocrButton.target = self
                ocrButton.action = #selector(performOCR(_:))
                objc_setAssociatedObject(ocrButton, "imageData", data, .OBJC_ASSOCIATION_RETAIN)
                objc_setAssociatedObject(ocrButton, "resultView", ocrResultView, .OBJC_ASSOCIATION_RETAIN)
                objc_setAssociatedObject(ocrButton, "textView", ocrTextView, .OBJC_ASSOCIATION_RETAIN)
                objc_setAssociatedObject(ocrButton, "copyButton", copyButton, .OBJC_ASSOCIATION_RETAIN)
                
                // Copy button action
                copyButton.target = self
                copyButton.action = #selector(copyOCRResult(_:))
                objc_setAssociatedObject(copyButton, "textView", ocrTextView, .OBJC_ASSOCIATION_RETAIN)
                
                NSLayoutConstraint.activate([
                    mainStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
                    mainStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
                    mainStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
                    mainStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10)
                ])
            }
            
        case .text(let text):
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            
            let textView = NSTextView()
            textView.isEditable = false
            textView.isSelectable = true
            textView.textContainerInset = NSSize(width: 10, height: 10)
            
            // Apply syntax highlighting if content looks like code
            let syntaxHighlighter = SyntaxHighlighter.shared
            if syntaxHighlighter.isLikelyCode(text),
               let highlighted = syntaxHighlighter.highlight(text) {
                textView.textStorage?.setAttributedString(highlighted)
                textView.backgroundColor = NSColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0) // Dark background for code
            } else {
                textView.string = text
                textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            }
            
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

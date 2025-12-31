import SwiftUI
import AppKit

// MARK: - Associated Object Keys
private var kImageDataKey: UInt8 = 0
private var kResultViewKey: UInt8 = 0
private var kTextViewKey: UInt8 = 0
private var kCopyButtonKey: UInt8 = 0

// MARK: - Preview Window Controller
class PreviewWindowController: NSObject, NSWindowDelegate {
    static let shared = PreviewWindowController()
    
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var globalEventMonitor: Any?  // For global key events when window loses focus
    private var currentItem: ClipboardItem?
    private var ocrResult: String?
    private var isPerformingOCR: Bool = false
    private weak var ocrButton: NSButton?
    private weak var copyOcrButton: NSButton?
    
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
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        panel?.title = "Preview - ESC/v close, ? help"
        panel?.isReleasedWhenClosed = false
        panel?.level = .floating
        panel?.delegate = self
        panel?.hidesOnDeactivate = false
        panel?.becomesKeyOnlyIfNeeded = false  // Allow panel to become key window
        
        // Create content directly with NSImageView/NSTextView
        panel?.contentView = createContentView(for: item)
        
        // Show panel
        panel?.makeKeyAndOrderFront(nil)
        
        // Store current item for shortcuts
        currentItem = item
        ocrResult = nil
        isPerformingOCR = false
        
        // Handle keyboard shortcuts
        let kb = KeyBindingManager.shared
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // ESC or v to close
            if event.keyCode == 53 || event.keyCode == 9 {
                self.close()
                return nil
            }
            
            // ? to show help
            if event.keyCode == 44 && event.modifierFlags.contains(.shift) {
                self.showHelpAlert()
                return nil
            }
            
            // Handle based on content type
            if case .image = item.content {
                // o for OCR
                if kb.matches(event, command: .previewOCR) && !self.isPerformingOCR {
                    self.triggerOCR()
                    return nil
                }
                // ⌘C to copy OCR result
                if kb.matches(event, command: .previewCopy) {
                    self.copyOCRResultViaKeyboard()
                    return nil
                }
            } else {
                // For non-image content, o opens in external app
                if kb.matches(event, command: .previewOpenExternal) {
                    self.openInExternalApp(item)
                    return nil
                }
            }
            
            return event
        }
        
        // Also add global monitor for ESC when window loses focus
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            // ESC to close (global monitor can't prevent event propagation, just close the window)
            if event.keyCode == 53 {
                self.close()
            }
        }
    }
    
    func close() {
        cleanup()
    }
    
    private func cleanup() {
        // Remove event monitors first
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        // Close panel
        panel?.close()
        panel = nil
        currentItem = nil
        ocrResult = nil
        isPerformingOCR = false
        
        // Reopen main popover after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AppDelegate.shared?.showMainPopover()
        }
    }
    
    // MARK: - Keyboard Shortcut Actions
    
    private func triggerOCR() {
        // Trigger the existing OCR button if available
        if let button = ocrButton, button.isEnabled {
            button.performClick(nil)
        }
    }
    
    private func copyOCRResultViaKeyboard() {
        // Trigger the existing copy button if available and visible
        if let button = copyOcrButton, !button.isHidden {
            button.performClick(nil)
        } else {
            // Fallback: copy from ocrResult if available
            guard let text = ocrResult, !text.isEmpty else {
                panel?.title = "Preview - No OCR result to copy"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.panel?.title = "Preview"
                }
                return
            }
            
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            panel?.title = "Preview - ✓ Copied!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.panel?.title = "Preview"
            }
        }
    }
    
    private func copyOCRResult() {
        guard let text = ocrResult, !text.isEmpty else {
            // Show feedback that there's nothing to copy
            let originalTitle = panel?.title
            panel?.title = "Preview - No OCR result to copy"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.panel?.title = originalTitle ?? "Preview"
            }
            return
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        // Show feedback
        panel?.title = "Preview - ✓ Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.panel?.title = "Preview - OCR complete (⌘C to copy)"
        }
    }
    
    private func showHelpAlert() {
        let kb = KeyBindingManager.shared
        let alert = NSAlert()
        alert.messageText = "Preview Shortcuts"
        
        if let item = currentItem, case .image = item.content {
            alert.informativeText = """
            \(kb.binding(for: .previewOCR).displayString) - Extract text (OCR)
            \(kb.binding(for: .previewCopy).displayString) - Copy OCR result
            ESC / v - Close preview
            """
        } else {
            alert.informativeText = """
            \(kb.binding(for: .previewOpenExternal).displayString) - Open in external app
            ESC / v - Close preview
            """
        }
        
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        guard let data = objc_getAssociatedObject(sender, &kImageDataKey) as? Data,
              let resultView = objc_getAssociatedObject(sender, &kResultViewKey) as? NSScrollView,
              let textView = objc_getAssociatedObject(sender, &kTextViewKey) as? NSTextView,
              let copyButton = objc_getAssociatedObject(sender, &kCopyButtonKey) as? NSButton else {
            print("[OCR] Failed to get associated objects")
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
                    textView.textColor = NSColor.labelColor
                    textView.font = NSFont.systemFont(ofSize: 12)
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
                    
                    // Force layout update
                    resultView.needsLayout = true
                    resultView.layoutSubtreeIfNeeded()
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
        guard let textView = objc_getAssociatedObject(sender, &kTextViewKey) as? NSTextView else {
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
                ocrResultView.borderType = .bezelBorder
                ocrResultView.backgroundColor = .textBackgroundColor
                
                let ocrTextView = NSTextView()
                ocrTextView.isEditable = false
                ocrTextView.isSelectable = true
                ocrTextView.font = NSFont.systemFont(ofSize: 12)
                ocrTextView.textContainerInset = NSSize(width: 8, height: 8)
                ocrTextView.backgroundColor = .textBackgroundColor
                ocrTextView.textColor = .textColor
                ocrTextView.autoresizingMask = [.width]
                ocrTextView.isVerticallyResizable = true
                ocrTextView.isHorizontallyResizable = false
                ocrTextView.textContainer?.widthTracksTextView = true
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
                objc_setAssociatedObject(ocrButton, &kImageDataKey, data, .OBJC_ASSOCIATION_RETAIN)
                objc_setAssociatedObject(ocrButton, &kResultViewKey, ocrResultView, .OBJC_ASSOCIATION_RETAIN)
                objc_setAssociatedObject(ocrButton, &kTextViewKey, ocrTextView, .OBJC_ASSOCIATION_RETAIN)
                objc_setAssociatedObject(ocrButton, &kCopyButtonKey, copyButton, .OBJC_ASSOCIATION_RETAIN)
                
                // Store references for keyboard shortcuts
                self.ocrButton = ocrButton
                self.copyOcrButton = copyButton
                
                // Copy button action
                copyButton.target = self
                copyButton.action = #selector(copyOCRResult(_:))
                objc_setAssociatedObject(copyButton, &kTextViewKey, ocrTextView, .OBJC_ASSOCIATION_RETAIN)
                
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
            textView.isEditable = false
            textView.isSelectable = true
            textView.textContainerInset = NSSize(width: 10, height: 10)
            
            if let attrString = NSAttributedString(rtf: data, documentAttributes: nil) {
                let plainText = attrString.string
                
                // Check if this is actually code that should be syntax highlighted
                let syntaxHighlighter = SyntaxHighlighter.shared
                if syntaxHighlighter.isLikelyCode(plainText),
                   let highlighted = syntaxHighlighter.highlight(plainText) {
                    textView.textStorage?.setAttributedString(highlighted)
                    textView.backgroundColor = NSColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0)
                } else {
                    // Show original rich text formatting
                    textView.textStorage?.setAttributedString(attrString)
                }
            }
            
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

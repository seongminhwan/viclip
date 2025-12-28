import SwiftUI
import AppKit

// MARK: - Large Text View
/// NSTextView wrapper for efficient rendering of large text content
struct LargeTextView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let maxPreviewLength: Int
    let showLineNumbers: Bool
    
    @Binding var isExpanded: Bool
    
    init(
        text: String,
        fontSize: Double = 13,
        maxPreviewLength: Int = 10_000,
        showLineNumbers: Bool = false,
        isExpanded: Binding<Bool> = .constant(false)
    ) {
        self.text = text
        self.fontSize = fontSize
        self.maxPreviewLength = maxPreviewLength
        self.showLineNumbers = showLineNumbers
        self._isExpanded = isExpanded
    }
    
    private var displayText: String {
        if isExpanded || text.count <= maxPreviewLength {
            return text
        }
        return String(text.prefix(maxPreviewLength)) + "\n\n... [Truncated: \(text.count.formatted()) characters total]"
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        
        scrollView.documentView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Only update if text changed
        if textView.string != displayText {
            textView.string = displayText
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }
}

// MARK: - Chunked Text View
/// For extremely large text, load in chunks
struct ChunkedTextView: View {
    let text: String
    let chunkSize: Int
    let fontSize: Double
    
    @State private var loadedChunks: Int = 1
    
    private var chunks: [String] {
        var result: [String] = []
        var start = text.startIndex
        
        while start < text.endIndex {
            let end = text.index(start, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            result.append(String(text[start..<end]))
            start = end
        }
        
        return result
    }
    
    private var displayedText: String {
        chunks.prefix(loadedChunks).joined()
    }
    
    private var hasMore: Bool {
        loadedChunks < chunks.count
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(displayedText)
                    .font(.system(size: fontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if hasMore {
                    Button(action: {
                        loadedChunks += 1
                    }) {
                        HStack {
                            Text("Load more (\(chunks.count - loadedChunks) chunks remaining)")
                            Image(systemName: "arrow.down.circle")
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .padding()
        }
    }
    
    init(text: String, chunkSize: Int = 5000, fontSize: Double = 13) {
        self.text = text
        self.chunkSize = chunkSize
        self.fontSize = fontSize
    }
}

// MARK: - Preview Area with Large Text Support
struct PreviewContentView: View {
    let content: ClipboardContent
    let fontSize: Double
    let maxPreviewLength: Int
    
    @State private var isExpanded = false
    
    var body: some View {
        Group {
            switch content {
            case .text(let string):
                if string.count > maxPreviewLength {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(string.count.formatted()) characters")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(isExpanded ? "Collapse" : "Show Full") {
                                isExpanded.toggle()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        LargeTextView(
                            text: string,
                            fontSize: fontSize,
                            maxPreviewLength: maxPreviewLength,
                            isExpanded: $isExpanded
                        )
                    }
                } else {
                    Text(string)
                        .font(.system(size: fontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
            case .richText(let data):
                if let attrString = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                    Text(AttributedString(attrString))
                        .font(.system(size: fontSize))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
            case .image(let data):
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
            case .fileURL(let path):
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: fontSize, weight: .medium))
                    
                    Text(path)
                        .font(.system(size: fontSize - 2))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

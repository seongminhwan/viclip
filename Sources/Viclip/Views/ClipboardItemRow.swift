import SwiftUI
import AppKit

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let isFocused: Bool  // Whether the history list has focus (not tag panel)
    let onPaste: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    let onAddToQueue: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Quick select number (1-9)
            // Quick select number (1-9) or Pin indicator
            if item.isPinnedItem || item.isDirectPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(width: 16)
            } else if index < 9 {
                Text("\(index + 1)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            } else {
                Spacer()
                    .frame(width: 16)
            }
            
            // Content type icon
            Image(systemName: item.content.icon)
                .foregroundColor(iconColor)
                .frame(width: 20)
            
            // Content preview
            VStack(alignment: .leading, spacing: 2) {
                contentPreview
                    .lineLimit(2)
                
                // Metadata
                HStack(spacing: 8) {
                    if let app = item.sourceApp {
                        Text(app)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(item.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("#\(item.position)")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Actions (visible on hover)
            if isHovered || isSelected {
                HStack(spacing: 4) {
                    // Add to queue
                    Button(action: onAddToQueue) {
                        Image(systemName: "plus.square")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Add to paste queue")
                    
                    // Favorite
                    Button(action: onToggleFavorite) {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .foregroundColor(item.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle favorite")
                    
                    // Delete
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
            
            // Favorite indicator (always visible if favorited)
            if item.isFavorite && !isHovered && !isSelected {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onPaste()
        }
        .onTapGesture {
            // Single tap could be used for selection
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    // MARK: - Computed Properties
    
    private var backgroundColor: Color {
        if isSelected {
            // Show dimmed selection when not focused (e.g., tag panel has focus)
            return Color.accentColor.opacity(isFocused ? 0.3 : 0.1)
        } else if isHovered {
            return Color(NSColor.selectedContentBackgroundColor).opacity(0.1)
        }
        return Color.clear
    }
    
    private var iconColor: Color {
        switch item.content {
        case .text:
            return .blue
        case .richText:
            return .purple
        case .image:
            return .green
        case .fileURL:
            return .orange
        }
    }
    
    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .text(let string):
            Text(string.replacingOccurrences(of: "\n", with: " "))
                .font(.system(.body, design: .default))
                .foregroundColor(.primary)
            
        case .richText:
            Text("[Rich Text Content]")
                .font(.system(.body, design: .default))
                .foregroundColor(.primary)
            
        case .image(let data):
            if let thumbnail = ThumbnailService.shared.thumbnail(for: data, id: item.id.uuidString) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 60)
            } else {
                Text("[Image]")
                    .font(.system(.body, design: .default))
                    .foregroundColor(.primary)
            }
            
        case .fileURL(let path):
            HStack {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(.body, design: .default))
                    .foregroundColor(.primary)
            }
        }
    }
}

#Preview {
    VStack {
        ClipboardItemRow(
            item: ClipboardItem(
                content: .text("Hello, World! This is a sample clipboard item."),
                sourceApp: "Safari",
                position: 1
            ),
            index: 0,
            isSelected: true,
            isFocused: true,
            onPaste: {},
            onDelete: {},
            onToggleFavorite: {},
            onAddToQueue: {}
        )
        
        ClipboardItemRow(
            item: ClipboardItem(
                content: .fileURL("/Users/test/Documents/file.pdf"),
                sourceApp: "Finder",
                position: 2,
                isFavorite: true
            ),
            index: 1,
            isSelected: false,
            isFocused: true,
            onPaste: {},
            onDelete: {},
            onToggleFavorite: {},
            onAddToQueue: {}
        )
    }
    .padding()
    .frame(width: 400)
}

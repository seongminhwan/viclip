import SwiftUI

// MARK: - Tag Manager Panel
struct TagManagerPanel: View {
    @ObservedObject var tagService = TagService.shared
    @Binding var selectedTagIndex: Int
    @Binding var isCreatingTag: Bool
    @Binding var isRenamingTag: Bool
    @Binding var editingTagName: String
    @Binding var isFocusedOnTags: Bool
    @Binding var isDeletingTagConfirm: Bool
    @Binding var tagToDelete: Tag?
    
    let theme: ThemeColors
    let onConfirmFilter: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(theme.accent)
                Text("Tags")
                    .font(.system(size: 12, weight: .semibold))
                
                Spacer()
                
                // Selected count
                if !tagService.selectedTagIds.isEmpty {
                    Text("\(tagService.selectedTagIds.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.accent)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.tertiaryBackground)
            
            Divider()
            
            // Tag List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(tagService.tags.enumerated()), id: \.element.id) { index, tag in
                            if isRenamingTag && index == selectedTagIndex {
                                // Inline rename input
                                TagInputRow(
                                    text: $editingTagName,
                                    placeholder: "Rename tag...",
                                    theme: theme,
                                    onConfirm: {
                                        if tagService.renameTag(id: tag.id, newName: editingTagName) {
                                            isRenamingTag = false
                                            editingTagName = ""
                                        }
                                    },
                                    onCancel: {
                                        isRenamingTag = false
                                        editingTagName = ""
                                    }
                                )
                                .id("rename-\(tag.id)")
                            } else {
                                TagRow(
                                    tag: tag,
                                    isSelected: tagService.isSelected(id: tag.id),
                                    isFocused: index == selectedTagIndex && isFocusedOnTags,
                                    theme: theme
                                )
                                .id(tag.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTagIndex = index
                                    tagService.toggleTagSelection(id: tag.id)
                                }
                            }
                        }
                        
                        // New tag input at end
                        if isCreatingTag {
                            TagInputRow(
                                text: $editingTagName,
                                placeholder: "New tag name...",
                                theme: theme,
                                onConfirm: {
                                    if let newTag = tagService.createTag(name: editingTagName) {
                                        isCreatingTag = false
                                        editingTagName = ""
                                        // Select the new tag
                                        if let index = tagService.tags.firstIndex(where: { $0.id == newTag.id }) {
                                            selectedTagIndex = index
                                        }
                                    }
                                },
                                onCancel: {
                                    isCreatingTag = false
                                    editingTagName = ""
                                }
                            )
                            .id("new-tag-input")
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selectedTagIndex) { newValue in
                    if newValue < tagService.tags.count {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(tagService.tags[newValue].id, anchor: .center)
                        }
                    }
                }
                .onChange(of: isCreatingTag) { newValue in
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo("new-tag-input", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Footer - show delete confirmation or hints
            if isDeletingTagConfirm, let tag = tagToDelete {
                VStack(spacing: 4) {
                    Text("Delete '\(tag.name)'?")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.text)
                    Text("Delete associated records too?")
                        .font(.system(size: 10))
                        .foregroundColor(theme.secondaryText)
                    HStack(spacing: 12) {
                        HStack(spacing: 2) {
                            Text("y")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.red)
                            Text("yes")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                        HStack(spacing: 2) {
                            Text("n/⏎")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.accent)
                            Text("no (default)")
                                .font(.system(size: 10))
                                .foregroundColor(theme.accent)
                        }
                    }
                }
                .padding(8)
                .background(theme.tertiaryBackground)
            } else {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        KeyHintSmall(key: "␣", action: "select", theme: theme)
                        KeyHintSmall(key: "⏎/l", action: "confirm", theme: theme)
                        KeyHintSmall(key: "n", action: "new", theme: theme)
                    }
                    HStack(spacing: 8) {
                        KeyHintSmall(key: "r", action: "rename", theme: theme)
                        KeyHintSmall(key: "d", action: "delete", theme: theme)
                        KeyHintSmall(key: "P", action: "pin", theme: theme)
                    }
                    HStack(spacing: 8) {
                        KeyHintSmall(key: "h/ESC", action: "back", theme: theme)
                    }
                }
                .padding(8)
                .background(theme.tertiaryBackground)
            }
        }
        .background(theme.background)
    }
}

// MARK: - Tag Row
struct TagRow: View {
    let tag: Tag
    let isSelected: Bool
    let isFocused: Bool
    let theme: ThemeColors
    
    @State private var isHovered = false
    
    private var backgroundColor: Color {
        if isFocused {
            return theme.accent.opacity(0.3)
        } else if isHovered {
            return theme.hover
        }
        return Color.clear
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Selection checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor(isSelected ? theme.accent : theme.secondaryText)
            
            // Tag color indicator
            if let colorHex = tag.color {
                Circle()
                    .fill(Color(hex: colorHex) ?? theme.accent)
                    .frame(width: 8, height: 8)
            }
            
            // Tag name
            Text(tag.name)
                .font(.system(size: 12))
                .foregroundColor(isFocused ? theme.text : (isSelected ? theme.accent : theme.text))
                .lineLimit(1)
            
            Spacer()
            
            // Pin indicator
            if tag.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? theme.accent : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Tag Input Row
struct TagInputRow: View {
    @Binding var text: String
    let placeholder: String
    let theme: ThemeColors
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 14))
                .foregroundColor(theme.accent)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit {
                    onConfirm()
                }
                .onExitCommand {
                    onCancel()
                }
            
            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.tertiaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.accent, lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Small Key Hint
struct KeyHintSmall: View {
    let key: String
    let action: String
    let theme: ThemeColors
    
    var body: some View {
        HStack(spacing: 2) {
            Text(key)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.primary)
            Text(action)
                .font(.system(size: 9))
                .foregroundColor(theme.secondaryText)
        }
    }
}

// MARK: - Color Extension for Hex
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

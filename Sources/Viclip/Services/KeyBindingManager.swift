import SwiftUI
import Carbon.HIToolbox

// MARK: - Key Binding Manager
class KeyBindingManager: ObservableObject {
    static let shared = KeyBindingManager()
    
    // Command types
    enum Command: String, CaseIterable, Identifiable {
        case moveUp = "Move Up"
        case moveDown = "Move Down"
        case moveToTop = "Move to Top"
        case moveToBottom = "Move to Bottom"
        case paste = "Paste Selected"
        case pasteAsPlainText = "Paste as Plain Text"
        case delete = "Delete Item"
        case favorite = "Toggle Favorite"
        case filterByType = "Filter by Type"
        case quickPreview = "Quick Preview"
        case search = "Search / Focus Input"
        case commandMenu = "Open Command Menu"
        case position = "Locate in Timeline"
        case addToQueue = "Add to Paste Queue"
        case escape = "Exit / Cancel"
        case advancedFilter = "Advanced Filter"
        case historyHalfPageUp = "History Half Page Up"
        case historyHalfPageDown = "History Half Page Down"
        
        // Preview mode commands
        case previewOCR = "OCR Extract Text"
        case previewCopy = "Copy Content"
        case previewScrollUp = "Scroll Up"
        case previewScrollDown = "Scroll Down"
        case previewHalfPageUp = "Half Page Up"
        case previewHalfPageDown = "Half Page Down"
        case previewOpenExternal = "Open External"
        
        var id: String { rawValue }
        
        var defaultBinding: KeyBinding {
            switch self {
            case .moveUp: return KeyBinding(key: "k", keyCode: 40, requiresShift: false)
            case .moveDown: return KeyBinding(key: "j", keyCode: 38, requiresShift: false)
            case .moveToTop: return KeyBinding(key: "gg", keyCode: 5, requiresShift: false, isSequence: true)
            case .moveToBottom: return KeyBinding(key: "G", keyCode: 5, requiresShift: true)
            case .paste: return KeyBinding(key: "⏎", keyCode: 36, requiresShift: false)
            case .pasteAsPlainText: return KeyBinding(key: "⌘⏎", keyCode: 36, requiresShift: false, requiresCommand: true)
            case .delete: return KeyBinding(key: "d", keyCode: 2, requiresShift: false)
            case .favorite: return KeyBinding(key: "⌃F", keyCode: 3, requiresShift: false, requiresControl: true)
            case .filterByType: return KeyBinding(key: "F", keyCode: 3, requiresShift: true)
            case .quickPreview: return KeyBinding(key: "v", keyCode: 9, requiresShift: false)
            case .search: return KeyBinding(key: "f", keyCode: 3, requiresShift: false)
            case .commandMenu: return KeyBinding(key: ":", keyCode: 41, requiresShift: true)
            case .position: return KeyBinding(key: "p", keyCode: 35, requiresShift: false)
            case .addToQueue: return KeyBinding(key: "q", keyCode: 12, requiresShift: false)
            case .escape: return KeyBinding(key: "⎋", keyCode: 53, requiresShift: false)
            case .advancedFilter: return KeyBinding(key: "⌘F", keyCode: 3, requiresShift: false, requiresCommand: true)
            case .historyHalfPageUp: return KeyBinding(key: "⌃U", keyCode: 32, requiresShift: false, requiresControl: true)
            case .historyHalfPageDown: return KeyBinding(key: "⌃D", keyCode: 2, requiresShift: false, requiresControl: true)
            
            // Preview mode bindings
            case .previewOCR: return KeyBinding(key: "o", keyCode: 31, requiresShift: false)
            case .previewCopy: return KeyBinding(key: "⌘C", keyCode: 8, requiresShift: false, requiresCommand: true)
            case .previewScrollUp: return KeyBinding(key: "k", keyCode: 40, requiresShift: false)
            case .previewScrollDown: return KeyBinding(key: "j", keyCode: 38, requiresShift: false)
            case .previewHalfPageUp: return KeyBinding(key: "⌘U", keyCode: 32, requiresShift: false, requiresCommand: true)
            case .previewHalfPageDown: return KeyBinding(key: "⌘D", keyCode: 2, requiresShift: false, requiresCommand: true)
            case .previewOpenExternal: return KeyBinding(key: "o", keyCode: 31, requiresShift: false)
            }
        }
    }
    
    // Key binding structure
    struct KeyBinding: Codable, Equatable {
        var key: String  // Display string
        var keyCode: UInt16
        var requiresShift: Bool
        var requiresCommand: Bool
        var requiresOption: Bool
        var requiresControl: Bool
        var isSequence: Bool  // For things like "gg"
        
        init(key: String, keyCode: UInt16, requiresShift: Bool = false, 
             requiresCommand: Bool = false, requiresOption: Bool = false,
             requiresControl: Bool = false, isSequence: Bool = false) {
            self.key = key
            self.keyCode = keyCode
            self.requiresShift = requiresShift
            self.requiresCommand = requiresCommand
            self.requiresOption = requiresOption
            self.requiresControl = requiresControl
            self.isSequence = isSequence
        }
        
        var displayString: String {
            var parts: [String] = []
            if requiresControl { parts.append("⌃") }
            if requiresOption { parts.append("⌥") }
            if requiresShift { parts.append("⇧") }
            if requiresCommand { parts.append("⌘") }
            parts.append(key)
            return parts.joined()
        }
        
        func matches(event: NSEvent) -> Bool {
            guard event.keyCode == keyCode else { return false }
            
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            // Check each modifier - if required, it must be present; if not required, it must be absent
            let shiftMatch = requiresShift == flags.contains(.shift)
            let commandMatch = requiresCommand == flags.contains(.command)
            let optionMatch = requiresOption == flags.contains(.option)
            let controlMatch = requiresControl == flags.contains(.control)
            
            return shiftMatch && commandMatch && optionMatch && controlMatch
        }
    }
    
    // Current bindings
    @Published var bindings: [Command: KeyBinding] = [:]
    @Published var lastConflict: (command: Command, conflictsWith: Command)? = nil
    
    private let storageKey = "customKeyBindings"
    
    private init() {
        loadBindings()
    }
    
    func binding(for command: Command) -> KeyBinding {
        bindings[command] ?? command.defaultBinding
    }
    
    /// Check if an event matches the binding for a command
    func matches(_ event: NSEvent, command: Command) -> Bool {
        return binding(for: command).matches(event: event)
    }
    
    /// Check if a binding conflicts with any existing binding
    func findConflict(for binding: KeyBinding, excluding: Command? = nil) -> Command? {
        for command in Command.allCases {
            if command == excluding { continue }
            
            let existingBinding = self.binding(for: command)
            if existingBinding.keyCode == binding.keyCode &&
               existingBinding.requiresShift == binding.requiresShift &&
               existingBinding.requiresCommand == binding.requiresCommand &&
               existingBinding.requiresOption == binding.requiresOption &&
               existingBinding.requiresControl == binding.requiresControl {
                return command
            }
        }
        return nil
    }
    
    /// Set binding with conflict detection. Returns the conflicting command if any.
    @discardableResult
    func setBinding(_ binding: KeyBinding, for command: Command) -> Command? {
        // Check for conflicts
        if let conflictingCommand = findConflict(for: binding, excluding: command) {
            lastConflict = (command, conflictingCommand)
            // Still allow the binding but notify
            bindings[command] = binding
            saveBindings()
            objectWillChange.send()
            return conflictingCommand
        }
        
        lastConflict = nil
        bindings[command] = binding
        saveBindings()
        objectWillChange.send()
        return nil
    }
    
    func resetToDefault(command: Command) {
        bindings.removeValue(forKey: command)
        lastConflict = nil
        saveBindings()
        objectWillChange.send()
    }
    
    func resetAllToDefaults() {
        bindings.removeAll()
        lastConflict = nil
        saveBindings()
        objectWillChange.send()
    }
    
    func command(for event: NSEvent, vimEngine: VIMEngine? = nil) -> Command? {
        // Check all bindings (including custom ones)
        for command in Command.allCases {
            let binding = self.binding(for: command)
            
            // Special handling for gg sequence
            if command == .moveToTop && binding.isSequence {
                if let engine = vimEngine,
                   event.keyCode == binding.keyCode,
                   !event.modifierFlags.contains(.shift) {
                    if engine.handleKeyPress("g") == .moveToTop {
                        return .moveToTop
                    }
                }
                continue  // Skip normal matching for sequence commands
            }
            
            // Normal binding matching
            if binding.matches(event: event) {
                return command
            }
        }
        
        return nil
    }
    
    // Arrow keys always work regardless of bindings
    func isArrowKey(_ event: NSEvent) -> Command? {
        switch event.keyCode {
        case 125: return .moveDown  // Down arrow
        case 126: return .moveUp    // Up arrow
        default: return nil
        }
    }
    
    // Number keys 1-9 for quick select
    func quickSelectNumber(_ event: NSEvent) -> Int? {
        guard let char = event.charactersIgnoringModifiers?.first,
              char.isNumber,
              let num = Int(String(char)),
              num >= 1 && num <= 9 else {
            return nil
        }
        return num
    }
    
    // MARK: - Persistence
    
    private func loadBindings() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: KeyBinding].self, from: data) else {
            return
        }
        
        for (key, binding) in decoded {
            if let command = Command(rawValue: key) {
                bindings[command] = binding
            }
        }
    }
    
    private func saveBindings() {
        var encoded: [String: KeyBinding] = [:]
        for (command, binding) in bindings {
            encoded[command.rawValue] = binding
        }
        
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Key Code to String Mapping
extension KeyBindingManager {
    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "o"
        case 32: return "u"
        case 33: return "["
        case 34: return "i"
        case 35: return "p"
        case 36: return "⏎"
        case 37: return "l"
        case 38: return "j"
        case 39: return "'"
        case 40: return "k"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "n"
        case 46: return "m"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "␣"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "?"
        }
    }
}

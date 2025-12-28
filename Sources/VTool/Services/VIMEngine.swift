import Foundation

// MARK: - VIM Mode Engine
class VIMEngine: ObservableObject {
    enum Mode {
        case normal
        case search
        case command
    }
    
    enum Command: Equatable {
        case moveUp
        case moveDown
        case moveToTop
        case moveToBottom
        case select
        case delete
        case toggleFavorite
        case search
        case escape
        case quickSelect(Int)
    }
    
    @Published var mode: Mode = .normal
    @Published var commandBuffer: String = ""
    @Published var searchQuery: String = ""
    
    private var pendingG = false
    
    func handleKeyPress(_ key: String, modifiers: Set<KeyModifier> = []) -> Command? {
        // Reset pending G if we get a different key
        if key != "g" && pendingG {
            pendingG = false
        }
        
        switch mode {
        case .normal:
            return handleNormalMode(key, modifiers: modifiers)
        case .search:
            return handleSearchMode(key, modifiers: modifiers)
        case .command:
            return handleCommandMode(key, modifiers: modifiers)
        }
    }
    
    private func handleNormalMode(_ key: String, modifiers: Set<KeyModifier>) -> Command? {
        // Quick select with numbers 1-9
        if let num = Int(key), num >= 1 && num <= 9 {
            return .quickSelect(num - 1)
        }
        
        switch key.lowercased() {
        case "j", "arrowdown":
            return .moveDown
            
        case "k", "arrowup":
            return .moveUp
            
        case "g":
            if pendingG {
                pendingG = false
                return .moveToTop
            } else {
                pendingG = true
                return nil
            }
            
        case "G", "arrowend":
            return .moveToBottom
            
        case "enter", "return":
            return .select
            
        case "d", "x", "backspace":
            return .delete
            
        case "f", "s":
            return .toggleFavorite
            
        case "/":
            mode = .search
            searchQuery = ""
            return .search
            
        case "escape":
            return .escape
            
        default:
            return nil
        }
    }
    
    private func handleSearchMode(_ key: String, modifiers: Set<KeyModifier>) -> Command? {
        switch key {
        case "escape":
            mode = .normal
            searchQuery = ""
            return .escape
            
        case "enter", "return":
            mode = .normal
            return .select
            
        default:
            return nil
        }
    }
    
    private func handleCommandMode(_ key: String, modifiers: Set<KeyModifier>) -> Command? {
        switch key {
        case "escape":
            mode = .normal
            commandBuffer = ""
            return .escape
            
        default:
            return nil
        }
    }
    
    func resetState() {
        mode = .normal
        commandBuffer = ""
        searchQuery = ""
        pendingG = false
    }
}

// MARK: - Key Modifier
enum KeyModifier {
    case command
    case shift
    case option
    case control
}

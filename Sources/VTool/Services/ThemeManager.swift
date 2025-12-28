import SwiftUI

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    enum ThemeMode: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        
        var id: String { rawValue }
    }
    
    @Published var themeMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode")
            updateColorScheme()
        }
    }
    
    @Published var fontSize: Double {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "fontSize")
        }
    }
    
    @Published var previewFontSize: Double {
        didSet {
            UserDefaults.standard.set(previewFontSize, forKey: "previewFontSize")
        }
    }
    
    @Published var colorScheme: ColorScheme?
    
    private init() {
        // Load saved values
        let savedMode = UserDefaults.standard.string(forKey: "themeMode") ?? "System"
        self.themeMode = ThemeMode(rawValue: savedMode) ?? .system
        self.fontSize = UserDefaults.standard.double(forKey: "fontSize")
        self.previewFontSize = UserDefaults.standard.double(forKey: "previewFontSize")
        
        // Set defaults if not set
        if fontSize == 0 { fontSize = 13 }
        if previewFontSize == 0 { previewFontSize = 14 }
        
        updateColorScheme()
    }
    
    func updateColorScheme() {
        switch themeMode {
        case .system:
            colorScheme = nil
        case .light:
            colorScheme = .light
        case .dark:
            colorScheme = .dark
        }
        objectWillChange.send()
    }
}

// MARK: - Theme Colors
struct ThemeColors {
    let background: Color
    let secondaryBackground: Color
    let tertiaryBackground: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let divider: Color
    let selection: Color
    let hover: Color
    
    static func forScheme(_ scheme: ColorScheme) -> ThemeColors {
        switch scheme {
        case .dark:
            return ThemeColors(
                background: Color(NSColor.windowBackgroundColor),
                secondaryBackground: Color(white: 0.15),
                tertiaryBackground: Color(white: 0.2),
                text: .white,
                secondaryText: Color(white: 0.6),
                accent: .blue,
                divider: Color(white: 0.25),
                selection: Color.blue.opacity(0.3),
                hover: Color(white: 0.25)
            )
        case .light:
            return ThemeColors(
                background: Color(NSColor.windowBackgroundColor),
                secondaryBackground: Color(white: 0.95),
                tertiaryBackground: Color(white: 0.98),
                text: .black,
                secondaryText: Color(white: 0.4),
                accent: .blue,
                divider: Color(white: 0.85),
                selection: Color.blue.opacity(0.15),
                hover: Color(white: 0.92)
            )
        @unknown default:
            return forScheme(.light)
        }
    }
}

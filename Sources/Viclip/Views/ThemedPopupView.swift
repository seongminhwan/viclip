import SwiftUI

// MARK: - Themed Wrapper View
struct ThemedPopupView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = AppLanguageManager.shared
    
    var body: some View {
        PopupWindowView()
            .preferredColorScheme(themeManager.colorScheme)
    }
}

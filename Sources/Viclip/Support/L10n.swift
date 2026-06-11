import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case english

    var id: String { rawValue }

    var localizationCode: String? {
        switch self {
        case .system: return nil
        case .zhHans: return "zh-Hans"
        case .english: return "en"
        }
    }

    var displayName: String {
        switch self {
        case .system: return L10n.t("language.system", "Follow System")
        case .zhHans: return L10n.t("language.zhHans", "中文")
        case .english: return L10n.t("language.english", "English")
        }
    }
}

final class AppLanguageManager: ObservableObject {
    static let shared = AppLanguageManager()

    private let storageKey = "appLanguage"

    @Published var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: storageKey)
        selectedLanguage = saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func localizedString(for key: String, fallback: String) -> String {
        NSLocalizedString(
            key,
            tableName: nil,
            bundle: activeBundle,
            value: fallback,
            comment: ""
        )
    }

    private var activeBundle: Bundle {
        guard let code = selectedLanguage.localizationCode else {
            return .module
        }

        let candidates = [
            code,
            code.lowercased(),
            code.replacingOccurrences(of: "-", with: "_"),
            code.replacingOccurrences(of: "-", with: "_").lowercased()
        ]

        for candidate in candidates {
            if let path = Bundle.module.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }

        return .module
    }
}

enum L10n {
    static func t(_ key: String, _ fallback: String) -> String {
        AppLanguageManager.shared.localizedString(for: key, fallback: fallback)
    }
}

extension Notification.Name {
    static let appLanguageChanged = Notification.Name("appLanguageChanged")
}

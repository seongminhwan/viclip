import Foundation

class PrivacyFilter: ObservableObject {
    @Published var rules: [PrivacyRule] = []
    
    private let rulesKey = "privacy_rules"
    
    // Default excluded apps (password managers)
    private let defaultExcludedBundleIds: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.lastpass.LastPass",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.dashlane.Dashlane"
    ]
    
    init() {
        loadRules()
    }
    
    // MARK: - Filtering
    
    func shouldExclude(bundleId: String) -> Bool {
        // Check default exclusions
        if defaultExcludedBundleIds.contains(bundleId) {
            return true
        }
        
        // Check custom rules
        return rules.contains { rule in
            rule.isEnabled && rule.appBundleId == bundleId
        }
    }
    
    func shouldExclude(text: String) -> Bool {
        // Check keyword rules
        for rule in rules where rule.isEnabled {
            if let keyword = rule.keyword, !keyword.isEmpty {
                if text.localizedCaseInsensitiveContains(keyword) {
                    return true
                }
            }
        }
        return false
    }
    
    // MARK: - Rule Management
    
    func addRule(_ rule: PrivacyRule) {
        rules.append(rule)
        saveRules()
    }
    
    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        saveRules()
    }
    
    func toggleRule(id: UUID) {
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index].isEnabled.toggle()
            saveRules()
        }
    }
    
    // MARK: - Persistence
    
    private func loadRules() {
        guard let data = UserDefaults.standard.data(forKey: rulesKey) else {
            return
        }
        
        let decoder = JSONDecoder()
        rules = (try? decoder.decode([PrivacyRule].self, from: data)) ?? []
    }
    
    private func saveRules() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(rules) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
    }
}

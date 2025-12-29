import Foundation
import AppKit
import Highlightr
import os.log

/// Service for syntax highlighting code content
class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()

    private static let logger = Logger(subsystem: "com.viclip.clipboard", category: "SyntaxHighlighter")

    private let highlightr: Highlightr?

    /// Whether the highlighter is available and working
    private(set) var isAvailable: Bool = false

    /// Error message if initialization failed
    private(set) var initializationError: String?

    /// Common code indicators for language detection
    private let languagePatterns: [(pattern: String, language: String)] = [
        // Swift
        ("import Foundation", "swift"),
        ("import SwiftUI", "swift"),
        ("import UIKit", "swift"),
        ("func ", "swift"),
        ("var ", "swift"),
        ("let ", "swift"),
        ("@State", "swift"),
        ("@Published", "swift"),
        ("struct ", "swift"),
        ("class ", "swift"),
        ("enum ", "swift"),
        
        // Python
        ("def ", "python"),
        ("import ", "python"),
        ("from ", "python"),
        ("if __name__", "python"),
        ("print(", "python"),
        
        // JavaScript/TypeScript
        ("const ", "javascript"),
        ("function ", "javascript"),
        ("=>", "javascript"),
        ("console.log", "javascript"),
        ("require(", "javascript"),
        ("export ", "typescript"),
        ("interface ", "typescript"),
        
        // HTML
        ("<!DOCTYPE", "html"),
        ("<html", "html"),
        ("<div", "html"),
        ("<span", "html"),
        
        // CSS
        ("{", "css"),
        ("color:", "css"),
        ("margin:", "css"),
        ("padding:", "css"),
        
        // JSON
        ("{\"", "json"),
        
        // Shell
        ("#!/bin/bash", "bash"),
        ("#!/bin/sh", "bash"),
        ("echo ", "bash"),
        
        // SQL
        ("SELECT ", "sql"),
        ("INSERT ", "sql"),
        ("UPDATE ", "sql"),
        ("CREATE TABLE", "sql"),
        
        // Go
        ("package main", "go"),
        ("func main()", "go"),
        
        // Rust
        ("fn main()", "rust"),
        ("impl ", "rust"),
        ("pub fn", "rust"),
        
        // Ruby
        ("require '", "ruby"),
        ("def ", "ruby"),
        ("class ", "ruby"),
        
        // PHP
        ("<?php", "php"),
        
        // Java/Kotlin
        ("public class", "java"),
        ("public static void main", "java"),
        ("fun ", "kotlin"),
        
        // C/C++
        ("#include", "cpp"),
        ("int main(", "cpp"),
        ("void ", "cpp"),
        
        // YAML
        ("---", "yaml"),
        
        // Markdown
        ("# ", "markdown"),
        ("## ", "markdown"),
        ("```", "markdown"),
    ]
    
    private init() {
        // Safely initialize Highlightr with error handling
        // This can fail if JSContext cannot be created (missing JIT entitlements)
        // Note: Highlightr uses JavaScriptCore which requires JIT entitlements
        // If the app is not properly signed, Highlightr() returns nil instead of crashing
        let tempHighlightr = Highlightr()
        var errorMessage: String? = nil

        if let h = tempHighlightr {
            h.setTheme(to: "atom-one-dark")
            Self.logger.info("SyntaxHighlighter initialized successfully")
        } else {
            errorMessage = "Syntax highlighting unavailable (Highlightr init failed - possibly missing JIT entitlements or resources)"
            Self.logger.warning("\(errorMessage!, privacy: .public)")
        }

        self.highlightr = tempHighlightr
        self.isAvailable = tempHighlightr != nil
        self.initializationError = errorMessage

        // Post notification for UI to potentially show warning
        if let error = errorMessage {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("SyntaxHighlighterInitializationFailed"),
                    object: nil,
                    userInfo: ["error": error]
                )
            }
        }
    }
    
    /// Check if content looks like code
    func isLikelyCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for common code patterns
        let codeIndicators = [
            "func ", "def ", "class ", "import ", "const ", "let ", "var ",
            "if (", "for (", "while (", "switch ", "return ", "=>",
            "{", "}", "()", "[];", "//", "/*", "#include", "#!"
        ]
        
        for indicator in codeIndicators {
            if trimmed.contains(indicator) {
                return true
            }
        }
        
        // Check for multiple lines with consistent indentation
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count >= 3 {
            let indentedLines = lines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }
            if Double(indentedLines.count) / Double(lines.count) > 0.3 {
                return true
            }
        }
        
        return false
    }
    
    /// Detect language from content
    func detectLanguage(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check patterns in order
        for (pattern, language) in languagePatterns {
            if trimmed.contains(pattern) {
                return language
            }
        }
        
        return nil
    }
    
    /// Highlight code and return attributed string
    /// Returns nil if highlighting is unavailable or fails (caller should use fallback plain text)
    func highlight(_ code: String, language: String? = nil) -> NSAttributedString? {
        guard isAvailable, let highlightr = highlightr else {
            // Silently return nil - caller should handle fallback
            return nil
        }

        let lang = language ?? detectLanguage(code) ?? "plaintext"

        // Wrap in autoreleasepool and catch any potential runtime issues
        var result: NSAttributedString? = nil
        autoreleasepool {
            result = highlightr.highlight(code, as: lang)
        }

        if result == nil {
            Self.logger.debug("Highlighting returned nil for language: \(lang, privacy: .public)")
        }

        return result
    }

    /// Highlight code for a specific theme
    /// Returns nil if highlighting is unavailable or fails (caller should use fallback plain text)
    func highlight(_ code: String, language: String? = nil, theme: String) -> NSAttributedString? {
        guard isAvailable, let highlightr = highlightr else {
            return nil
        }

        highlightr.setTheme(to: theme)
        let lang = language ?? detectLanguage(code) ?? "plaintext"

        var result: NSAttributedString? = nil
        autoreleasepool {
            result = highlightr.highlight(code, as: lang)
        }

        return result
    }
    
    /// Get appropriate theme based on appearance
    func themeForAppearance(_ isDark: Bool) -> String {
        return isDark ? "atom-one-dark" : "atom-one-light"
    }
    
    /// Update theme for current appearance
    func updateTheme(isDark: Bool) {
        highlightr?.setTheme(to: themeForAppearance(isDark))
    }
}

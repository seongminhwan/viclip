import Foundation
import AppKit
import Highlightr

/// Service for syntax highlighting code content
class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()
    
    private let highlightr: Highlightr?
    
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
        // Try multiple bundle paths for Highlightr resources
        highlightr = Self.createHighlightr()
        highlightr?.setTheme(to: "atom-one-dark")
    }
    
    /// Create Highlightr instance with correct bundle path
    private static func createHighlightr() -> Highlightr? {
        // First try default initialization (works with swift run)
        if let instance = Highlightr() {
            return instance
        }
        
        // For packaged app, try to find resources in app bundle
        let resourceBundle = Bundle.main.resourceURL?
            .appendingPathComponent("Highlightr_Highlightr.bundle")
        
        if let bundlePath = resourceBundle?.path,
           let bundle = Bundle(path: bundlePath),
           let highlightPath = bundle.path(forResource: "highlight.min", ofType: "js") {
            return Highlightr(highlightPath: highlightPath)
        }
        
        // Try Contents/Resources directly
        if let appPath = Bundle.main.bundlePath as String?,
           let bundle = Bundle(path: "\(appPath)/Contents/Resources/Highlightr_Highlightr.bundle"),
           let highlightPath = bundle.path(forResource: "highlight.min", ofType: "js") {
            return Highlightr(highlightPath: highlightPath)
        }
        
        print("[SyntaxHighlighter] Failed to find Highlightr resources")
        return nil
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
    func highlight(_ code: String, language: String? = nil) -> NSAttributedString? {
        guard let highlightr = highlightr else { return nil }
        
        let lang = language ?? detectLanguage(code) ?? "plaintext"
        return highlightr.highlight(code, as: lang)
    }
    
    /// Highlight code for a specific theme
    func highlight(_ code: String, language: String? = nil, theme: String) -> NSAttributedString? {
        guard let highlightr = highlightr else { return nil }
        
        highlightr.setTheme(to: theme)
        let lang = language ?? detectLanguage(code) ?? "plaintext"
        return highlightr.highlight(code, as: lang)
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

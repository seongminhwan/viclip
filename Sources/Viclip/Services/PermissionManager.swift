import Foundation
import AppKit
import os.log

/// Manages permission checks and user guidance for required system permissions
class PermissionManager {
    static let shared = PermissionManager()
    
    private let logger = Logger(subsystem: "com.viclip.clipboard", category: "Permissions")
    
    /// Check if we have Automation permission to control System Events
    /// Returns: true if permission granted, false if denied or not determined
    func checkAutomationPermission() -> Bool {
        // Test with an actual keystroke-like command that requires full permission
        // We use "key code 0" with no modifiers - this is a no-op but requires permission
        let testScript = """
        tell application "System Events"
            -- This requires the same permission as keystroke
            set frontApp to name of first application process whose frontmost is true
            return frontApp
        end tell
        """
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: testScript) {
            script.executeAndReturnError(&error)
            
            if let error = error {
                let errorNumber = error["NSAppleScriptErrorNumber"] as? Int ?? 0
                logger.warning("Permission check error: \(errorNumber) - \(error["NSAppleScriptErrorBriefMessage"] as? String ?? "unknown")")
                // -1743 = "Not authorized to send Apple events"
                if errorNumber == -1743 {
                    logger.warning("Automation permission denied for System Events")
                    return false
                }
                // Other errors also mean we don't have proper access
                return false
            } else {
                logger.info("Automation permission granted for System Events")
                return true
            }
        }
        
        return false
    }
    
    /// Check if we have Accessibility permission using AXIsProcessTrusted
    func checkAccessibilityPermission() -> Bool {
        let isTrusted = AXIsProcessTrusted()
        logger.info("Accessibility permission status: \(isTrusted)")
        return isTrusted
    }
    
    /// Check permissions and show dialog if needed
    /// Call this on app launch
    func checkAndRequestPermissions() {
        logger.info("checkAndRequestPermissions: Starting permission check")
        
        // Check both permissions
        let hasAutomation = checkAutomationPermission()
        let hasAccessibility = checkAccessibilityPermission()
        
        logger.info("Permissions status: Automation=\(hasAutomation), Accessibility=\(hasAccessibility)")
        
        if hasAutomation && hasAccessibility {
            logger.info("All required permissions granted")
            return
        }
        
        logger.warning("Permissions not granted (Auto=\(hasAutomation), Access=\(hasAccessibility)), triggering system prompt")
        
        // If accessibility is missing, we can just request it via AXIsProcessTrustedWithOptions
        if !hasAccessibility {
            // This will show the system dialog for Accessibility
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        
        // If automation is missing, trigger it
        if !hasAutomation {
            triggerSystemPermissionPrompt()
        }
        
        // Show our guidance dialog after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
           self?.showPermissionDialog(missingAccessibility: !hasAccessibility)
        }
    }
    
    /// Trigger the system permission dialog by attempting to use System Events
    private func triggerSystemPermissionPrompt() {
        // This script will trigger the macOS permission dialog
        let triggerScript = """
        tell application "System Events"
            keystroke ""
        end tell
        """
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: triggerScript) {
            script.executeAndReturnError(&error)
            
            if let error = error {
                let errorNumber = error["NSAppleScriptErrorNumber"] as? Int ?? 0
                logger.info("Trigger script result: \(errorNumber)")
                // We rely on the caller to show the guidance dialog
            }
        }
    }
    
    /// Show a user-friendly dialog explaining what permissions are needed
    private func showPermissionDialog(missingAccessibility: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = "Viclip Needs Permission"
            
            var infoText = "To paste clipboard content into other applications, Viclip needs system permissions.\n\nPlease enable Viclip in System Settings:\n"
            
            if missingAccessibility {
                infoText += "1. Privacy & Security → Accessibility\n"
            }
            
            infoText += "2. Privacy & Security → Automation → Viclip → System Events\n"
            infoText += "\nAfter enabling, the paste feature will work automatically."
            
            alert.informativeText = infoText
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            
            // Add app icon if available
            if let icon = NSImage(named: "AppIcon") {
                alert.icon = icon
            }
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                self?.openAutomationSettings(openAccessibility: missingAccessibility)
            }
        }
    }
    
    /// Open System Preferences to the appropriate section
    func openAutomationSettings(openAccessibility: Bool = false) {
        if openAccessibility {
            // Open Accessibility settings
            let preString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            if let url = URL(string: preString) {
                NSWorkspace.shared.open(url)
                return
            }
        }
        
        // Try the direct URL first (works on macOS 13+)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
            logger.info("Opened Automation settings via URL")
        } else {
            // Fallback: open Privacy & Security
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                NSWorkspace.shared.open(url)
                logger.info("Opened Privacy settings via URL")
            }
        }
    }
    
    /// Show a toast/notification that paste failed due to permissions
    func showPermissionRequiredNotification() {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = "Paste Failed"
            alert.informativeText = "Viclip doesn't have permission to paste. Click 'Fix Now' to grant permission."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Fix Now")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                self?.openAutomationSettings()
            }
        }
    }
}

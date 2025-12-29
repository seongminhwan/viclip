//
//  Highlightr.swift
//  Pods
//
//  Created by Illanes, J.P. on 4/10/16.
//
//

import Foundation
import JavaScriptCore
import os.log

#if os(OSX)
    import AppKit
#endif

/// Utility class for generating a highlighted NSAttributedString from a String.
open class Highlightr
{
    /// Returns the current Theme.
    open var theme : Theme!
    {
        didSet
        {
            themeChanged?(theme)
        }
    }
    
    /// This block will be called every time the theme changes.
    open var themeChanged : ((Theme) -> Void)?

    /// Defaults to `false` - when `true`, forces highlighting to finish even if illegal syntax is detected.
    open var ignoreIllegals = false

    private let hljs: JSValue
    private let bundle : Bundle
    
    /// Logger for debugging bundle resolution issues
    private static let logger = Logger(subsystem: "com.viclip.highlightr", category: "BundleResolution")
    private let htmlStart = "<"
    private let spanStart = "span class=\""
    private let spanStartClose = "\">"
    private let spanEnd = "/span>"
    private let htmlEscape = try! NSRegularExpression(pattern: "&#?[a-zA-Z0-9]+?;", options: .caseInsensitive)
    
    /**
     Default init method.

     - parameter highlightPath: The path to `highlight.min.js`. Defaults to `Highlightr.framework/highlight.min.js`

     - returns: Highlightr instance.
     */
    public init?(highlightPath: String? = nil)
    {
        Self.logger.info("Highlightr init starting...")
        
        guard let jsContext = JSContext() else {
            Self.logger.error("Failed to create JSContext")
            return nil
        }
        let window = JSValue(newObjectIn: jsContext)

        // Use multi-strategy bundle resolution for packaged apps
        guard let resolvedBundle = Self.findResourceBundle() else {
            Self.logger.error("Failed to find resource bundle - all strategies failed")
            return nil
        }
        self.bundle = resolvedBundle
        
        Self.logger.info("Using bundle at path: \(resolvedBundle.bundlePath, privacy: .public)")
        
        guard let hgPath = highlightPath ?? resolvedBundle.path(forResource: "highlight.min", ofType: "js") else
        {
            Self.logger.error("highlight.min.js not found in bundle")
            return nil
        }
        
        Self.logger.info("Found highlight.min.js at: \(hgPath, privacy: .public)")
        
        guard let hgJs = try? String.init(contentsOfFile: hgPath) else {
            Self.logger.error("Failed to read highlight.min.js contents")
            return nil
        }
        let value = jsContext.evaluateScript(hgJs)
        guard let hljs = jsContext.objectForKeyedSubscript("hljs") else {
            Self.logger.error("Failed to get hljs object from JSContext")
            return nil
        }

        self.hljs = hljs
        
        guard setTheme(to: "pojoaque") else
        {
            Self.logger.error("Failed to set initial theme")
            return nil
        }
        
        Self.logger.info("Highlightr initialized successfully")
    }
    
    /**
     Set the theme to use for highlighting.
     
     - parameter to: Theme name
     
     - returns: true if it was possible to set the given theme, false otherwise
     */
    @discardableResult
    open func setTheme(to name: String) -> Bool
    {
        guard let defTheme = bundle.path(forResource: name+".min", ofType: "css") else
        {
            return false
        }
        guard let themeString = try? String.init(contentsOfFile: defTheme) else { return false }
        theme =  Theme(themeString: themeString)

        
        return true
    }
    
    /**
     Takes a String and returns a NSAttributedString with the given language highlighted.
     
     - parameter code:           Code to highlight.
     - parameter languageName:   Language name or alias. Set to `nil` to use auto detection.
     - parameter fastRender:     Defaults to true - When *true* will use the custom made html parser rather than Apple's solution.
     
     - returns: NSAttributedString with the detected code highlighted.
     */
    open func highlight(_ code: String, as languageName: String? = nil, fastRender: Bool = true) -> NSAttributedString?
    {
        let ret: JSValue?
        if let languageName = languageName
        {
            let result: JSValue = hljs.invokeMethod("highlight", withArguments: [languageName, code, ignoreIllegals])
			 if result.isUndefined {
				// If highlighting failed, use highlightAuto
				ret = hljs.invokeMethod("highlightAuto", withArguments: [code])
			} else {
				ret = result
			}
        }else
        {
            // language auto detection
            ret = hljs.invokeMethod("highlightAuto", withArguments: [code])
        }

        guard let res = ret?.objectForKeyedSubscript("value"), var string = res.toString() else
        {
            return nil
        }
        
        var returnString : NSAttributedString?
        if(fastRender)
        {
            returnString = processHTMLString(string)
        }else
        {
            string = "<style>"+theme.lightTheme+"</style><pre><code class=\"hljs\">"+string+"</code></pre>"
            let opt: [NSAttributedString.DocumentReadingOptionKey : Any] = [
             .documentType: NSAttributedString.DocumentType.html,
             .characterEncoding: String.Encoding.utf8.rawValue
             ]
            
            guard let data = string.data(using: String.Encoding.utf8) else { return nil }
            safeMainSync
            {
                returnString = try? NSMutableAttributedString(data:data, options: opt, documentAttributes:nil)
            }
        }
        
        return returnString
    }
    
    /**
     Returns a list of all the available themes.
     
     - returns: Array of Strings
     */
    open func availableThemes() -> [String]
    {
        let paths = bundle.paths(forResourcesOfType: "css", inDirectory: nil) as [NSString]
        var result = [String]()
        for path in paths {
            result.append(path.lastPathComponent.replacingOccurrences(of: ".min.css", with: ""))
        }
        
        return result
    }
    
    /**
     Returns a list of all supported languages.
     
     - returns: Array of Strings
     */
    open func supportedLanguages() -> [String]
    {
        let res = hljs.invokeMethod("listLanguages", withArguments: [])
        return (res?.toArray() as? [String]) ?? []
    }
    
    /**
     Execute the provided block in the main thread synchronously.
     */
    private func safeMainSync(_ block: @escaping ()->())
    {
        if Thread.isMainThread
        {
            block()
        }else
        {
            DispatchQueue.main.sync { block() }
        }
    }
    
    /**
     Find the resource bundle using multiple strategies for packaged apps.
     This handles both SwiftPM development and packaged .app bundle scenarios.
     */
    private static func findResourceBundle() -> Bundle? {
        logger.info("Starting bundle resolution...")
        logger.info("Main bundle path: \(Bundle.main.bundlePath, privacy: .public)")
        logger.info("Main executable path: \(Bundle.main.executablePath ?? "nil", privacy: .public)")
        
        // Strategy 1: Try Bundle.module (works in SwiftPM development)
        #if SWIFT_PACKAGE
        logger.info("Strategy 1: Trying Bundle.module (SWIFT_PACKAGE is defined)")
        let moduleBundle = Bundle.module
        logger.info("Bundle.module path: \(moduleBundle.bundlePath, privacy: .public)")
        if moduleBundle.path(forResource: "highlight.min", ofType: "js") != nil {
            logger.info("Strategy 1 SUCCESS: Found resources in Bundle.module")
            return moduleBundle
        } else {
            logger.warning("Strategy 1 FAILED: highlight.min.js not found in Bundle.module")
        }
        #else
        logger.info("Strategy 1: SWIFT_PACKAGE not defined, skipping Bundle.module")
        #endif
        
        // Strategy 2: Look for bundle in main app's resources (packaged app)
        logger.info("Strategy 2: Looking for Highlightr_Highlightr.bundle in main app resources")
        if let bundlePath = Bundle.main.path(forResource: "Highlightr_Highlightr", ofType: "bundle") {
            logger.info("Found bundle at: \(bundlePath, privacy: .public)")
            if let bundle = Bundle(path: bundlePath) {
                if bundle.path(forResource: "highlight.min", ofType: "js") != nil {
                    logger.info("Strategy 2 SUCCESS: Found resources in Highlightr_Highlightr.bundle")
                    return bundle
                } else {
                    logger.warning("Strategy 2 FAILED: Bundle found but highlight.min.js missing")
                }
            } else {
                logger.warning("Strategy 2 FAILED: Could not create Bundle from path")
            }
        } else {
            logger.warning("Strategy 2 FAILED: Highlightr_Highlightr.bundle not found in main resources")
        }
        
        // Strategy 3: Try finding bundle relative to executable
        logger.info("Strategy 3: Looking for bundle relative to executable")
        if let execPath = Bundle.main.executablePath {
            let resourcePath = (execPath as NSString)
                .deletingLastPathComponent
                .appending("/../Resources/Highlightr_Highlightr.bundle")
            logger.info("Trying path: \(resourcePath, privacy: .public)")
            if let bundle = Bundle(path: resourcePath) {
                if bundle.path(forResource: "highlight.min", ofType: "js") != nil {
                    logger.info("Strategy 3 SUCCESS: Found resources in relative bundle path")
                    return bundle
                } else {
                    logger.warning("Strategy 3 FAILED: Bundle found but highlight.min.js missing")
                }
            } else {
                logger.warning("Strategy 3 FAILED: Could not create Bundle from path")
            }
        } else {
            logger.warning("Strategy 3 FAILED: No executable path available")
        }
        
        // Strategy 4: Fallback to Bundle(for: Highlightr.self) for framework builds
        logger.info("Strategy 4: Trying Bundle(for: Highlightr.self)")
        let classBundle = Bundle(for: Highlightr.self)
        logger.info("Class bundle path: \(classBundle.bundlePath, privacy: .public)")
        if classBundle.path(forResource: "highlight.min", ofType: "js") != nil {
            logger.info("Strategy 4 SUCCESS: Found resources in class bundle")
            return classBundle
        } else {
            logger.warning("Strategy 4 FAILED: highlight.min.js not found in class bundle")
        }
        
        // List contents of Resources directory for debugging
        logger.error("All strategies failed. Listing main bundle resources for debugging:")
        if let resourcePath = Bundle.main.resourcePath {
            logger.info("Resource path: \(resourcePath, privacy: .public)")
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                for item in contents.prefix(20) {
                    logger.info("  - \(item, privacy: .public)")
                }
            }
        }
        
        return nil
    }
    
    private func processHTMLString(_ string: String) -> NSAttributedString?
    {
        let scanner = Scanner(string: string)
        scanner.charactersToBeSkipped = nil
        var scannedString: NSString?
        let resultString = NSMutableAttributedString(string: "")
        var propStack = ["hljs"]
        
        while !scanner.isAtEnd
        {
            var ended = false
            if scanner.scanUpTo(htmlStart, into: &scannedString)
            {
                if scanner.isAtEnd
                {
                    ended = true
                }
            }
            
            if scannedString != nil && scannedString!.length > 0 {
                let attrScannedString = theme.applyStyleToString(scannedString! as String, styleList: propStack)
                resultString.append(attrScannedString)
                if ended
                {
                    continue
                }
            }
            
            scanner.scanLocation += 1
            
            let string = scanner.string as NSString
            let nextChar = string.substring(with: NSMakeRange(scanner.scanLocation, 1))
            if(nextChar == "s")
            {
                scanner.scanLocation += (spanStart as NSString).length
                scanner.scanUpTo(spanStartClose, into:&scannedString)
                scanner.scanLocation += (spanStartClose as NSString).length
                propStack.append(scannedString! as String)
            }
            else if(nextChar == "/")
            {
                scanner.scanLocation += (spanEnd as NSString).length
                propStack.removeLast()
            }else
            {
                let attrScannedString = theme.applyStyleToString("<", styleList: propStack)
                resultString.append(attrScannedString)
                scanner.scanLocation += 1
            }
            
            scannedString = nil
        }
        
        let results = htmlEscape.matches(in: resultString.string,
                                               options: [.reportCompletion],
                                               range: NSMakeRange(0, resultString.length))
        var locOffset = 0
        for result in results
        {
            let fixedRange = NSMakeRange(result.range.location-locOffset, result.range.length)
            let entity = (resultString.string as NSString).substring(with: fixedRange)
            if let decodedEntity = HTMLUtils.decode(entity)
            {
                resultString.replaceCharacters(in: fixedRange, with: String(decodedEntity))
                locOffset += result.range.length-1;
            }
            

        }

        return resultString
    }
    
}

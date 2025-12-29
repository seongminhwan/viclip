import Foundation
import AppKit
import Vision

/// OCR Service using macOS Vision framework
class OCRService {
    static let shared = OCRService()
    
    enum OCRError: Error, LocalizedError {
        case invalidImage
        case noResults
        case processingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Unable to process image"
            case .noResults:
                return "No text found in image"
            case .processingFailed(let message):
                return "OCR failed: \(message)"
            }
        }
    }
    
    private init() {}
    
    /// Recognize text from image data
    func recognizeText(from data: Data, languages: [String] = ["zh-Hans", "zh-Hant", "en-US"]) async throws -> String {
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.processingFailed(error.localizedDescription))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(throwing: OCRError.noResults)
                    return
                }
                
                // Extract text from observations
                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                let text = recognizedStrings.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            
            // Configure recognition
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true
            
            // Create handler and perform
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.processingFailed(error.localizedDescription))
            }
        }
    }
    
    /// Recognize text from NSImage
    func recognizeText(from image: NSImage, languages: [String] = ["zh-Hans", "zh-Hant", "en-US"]) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.processingFailed(error.localizedDescription))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(throwing: OCRError.noResults)
                    return
                }
                
                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                let text = recognizedStrings.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.processingFailed(error.localizedDescription))
            }
        }
    }
}

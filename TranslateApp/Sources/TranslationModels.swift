import Foundation

struct TranslationResult: Sendable, Equatable {
    let translatedText: String
    let detectedSourceLanguage: String?
}

enum TranslationError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidRequest
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add a Google Cloud Translation API key in Settings."
        case .invalidRequest:
            "The text could not be prepared for translation."
        case .invalidResponse:
            "Google Translation returned an invalid response."
        case .service(let message):
            message
        }
    }
}

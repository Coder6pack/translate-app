import Foundation

actor GoogleTranslationClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(text: String, targetLanguage: String, apiKey: String) async throws -> TranslationResult {
        guard !text.isEmpty, !targetLanguage.isEmpty, !apiKey.isEmpty else {
            throw TranslationError.invalidRequest
        }

        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else { throw TranslationError.invalidRequest }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            RequestBody(q: text, target: targetLanguage, format: "text")
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if let error = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw TranslationError.service(error.error.message)
            }
            throw TranslationError.service("Google Translation request failed (HTTP \(httpResponse.statusCode)).")
        }

        let envelope = try decoder.decode(ResponseEnvelope.self, from: data)
        guard let translation = envelope.data.translations.first else {
            throw TranslationError.invalidResponse
        }
        return TranslationResult(
            translatedText: translation.translatedText,
            detectedSourceLanguage: translation.detectedSourceLanguage
        )
    }
}

private extension GoogleTranslationClient {
    struct RequestBody: Encodable {
        let q: String
        let target: String
        let format: String
    }

    struct ResponseEnvelope: Decodable {
        let data: ResponseData
    }

    struct ResponseData: Decodable {
        let translations: [Translation]
    }

    struct Translation: Decodable {
        let translatedText: String
        let detectedSourceLanguage: String?
    }

    struct ErrorEnvelope: Decodable {
        let error: ServiceError
    }

    struct ServiceError: Decodable {
        let message: String
    }
}

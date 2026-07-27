import Foundation

enum AIProvider: String, CaseIterable, Codable {
    case anthropic
    case openai
    case deepseek
    case gemini

    var displayName: String {
        switch self {
        case .anthropic: "Claude"
        case .openai:    "ChatGPT"
        case .deepseek:  "DeepSeek"
        case .gemini:    "Gemini"
        }
    }

    /// Fallback source for a key when `secrets.json` has none for this provider.
    var environmentVariable: String {
        switch self {
        case .anthropic: "ANTHROPIC_API_KEY"
        case .openai:    "OPENAI_API_KEY"
        case .deepseek:  "DEEPSEEK_API_KEY"
        case .gemini:    "GEMINI_API_KEY"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .anthropic: "https://api.anthropic.com/v1/messages"
        case .openai:    "https://api.openai.com/v1/chat/completions"
        case .deepseek:  "https://api.deepseek.com/v1/chat/completions"
        case .gemini:    "https://generativelanguage.googleapis.com/v1beta/models"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5"
        case .openai:    "gpt-4o"
        case .deepseek:  "deepseek-v4-flash"
        case .gemini:    "gemini-2.5-flash"
        }
    }

    var models: [String] {
        switch self {
        case .anthropic:
            ["claude-opus-5", "claude-sonnet-5", "claude-opus-4-8", "claude-haiku-4-5"]
        case .openai:
            ["gpt-4o", "gpt-4.1", "o4-mini", "o3-mini"]
        case .deepseek:
            ["deepseek-v4-flash", "deepseek-v4-pro"]
        case .gemini:
            ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"]
        }
    }
}

/// A failure that is worth showing the student, rather than silently denying.
struct AiError: Error {
    let message: String
}

struct AiClient {
    let apiKey: String
    let endpoint: String
    let model: String
    let provider: AIProvider

    init(apiKey: String, endpoint: String, model: String, provider: AIProvider = .anthropic) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.provider = provider
    }

    // MARK: - Chat

    func chat(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AiError(message: "No API key set for \(provider.displayName). Add one in Settings.")
        }
        guard let url = buildURL() else {
            throw AiError(message: "Invalid API endpoint: \(endpoint)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setAuthHeaders(&req)
        req.timeoutInterval = 60

        guard let body = buildBody(system: system, user: user) else {
            throw AiError(message: "Could not encode the request.")
        }
        req.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AiError(message: "Could not reach \(provider.displayName): \(error.localizedDescription)")
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = apiErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw AiError(message: "\(provider.displayName) rejected the request: \(detail)")
        }

        let text = extractText(from: data)
        guard !text.isEmpty else {
            let detail = apiErrorMessage(from: data) ?? "empty response"
            throw AiError(message: "\(provider.displayName) returned no usable answer (\(detail)).")
        }
        return text
    }

    /// Every provider nests its error text under `error.message`.
    private func apiErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let err = json["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
        if let msg = json["message"] as? String { return msg }
        return nil
    }

    // MARK: - URL Building

    private func buildURL() -> URL? {
        switch provider {
        case .gemini:
            return URL(string: "\(endpoint)/\(model):generateContent")
        default:
            return URL(string: endpoint)
        }
    }

    // MARK: - Auth

    private func setAuthHeaders(_ req: inout URLRequest) {
        switch provider {
        case .anthropic:
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openai, .deepseek:
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .gemini:
            req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
    }

    // MARK: - Body Building

    private func buildBody(system: String, user: String) -> Data? {
        switch provider {
        case .anthropic:
            let body: [String: Any] = [
                "model": model,
                "max_tokens": 1024,
                "system": system,
                "messages": [["role": "user", "content": user]]
            ]
            return try? JSONSerialization.data(withJSONObject: body)

        case .openai, .deepseek:
            var body: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user]
                ]
            ]
            // OpenAI reasoning models (o1/o3/o4…) reject `max_tokens` outright.
            if provider == .openai && isReasoningModel {
                body["max_completion_tokens"] = 4096 // reasoning tokens count against this
            } else {
                body["max_tokens"] = 1024
            }
            return try? JSONSerialization.data(withJSONObject: body)

        case .gemini:
            let body: [String: Any] = [
                "system_instruction": ["parts": [["text": system]]],
                "contents": [
                    ["role": "user", "parts": [["text": user]]]
                ],
                // 2.5 models spend part of this budget on thinking, so leave headroom.
                "generationConfig": ["maxOutputTokens": 4096]
            ]
            return try? JSONSerialization.data(withJSONObject: body)
        }
    }

    private var isReasoningModel: Bool {
        let m = model.lowercased()
        return m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4")
    }

    // MARK: - Response Parsing

    private func extractText(from data: Data) -> String {
        switch provider {
        case .anthropic:
            return extractAnthropic(data)
        case .openai, .deepseek:
            return extractOpenAI(data)
        case .gemini:
            return extractGemini(data)
        }
    }

    private func extractAnthropic(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else { return "" }
        // Skip thinking blocks; concatenate the text ones.
        return content
            .filter { $0["type"] as? String == "text" || $0["text"] != nil }
            .compactMap { $0["text"] as? String }
            .joined()
    }

    private func extractOpenAI(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else { return "" }
        return text
    }

    private func extractGemini(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return "" }
        return parts.compactMap { $0["text"] as? String }.joined()
    }
}

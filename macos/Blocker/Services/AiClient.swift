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
        case .anthropic: "claude-sonnet-4-6"
        case .openai:    "gpt-4o"
        case .deepseek:  "deepseek-chat"
        case .gemini:    "gemini-2.5-flash"
        }
    }

    var models: [String] {
        switch self {
        case .anthropic:
            ["claude-opus-4-20250514", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
        case .openai:
            ["gpt-4o", "gpt-4.1", "o4-mini", "o3-mini"]
        case .deepseek:
            ["deepseek-chat", "deepseek-reasoner"]
        case .gemini:
            ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"]
        }
    }
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

    func chat(system: String, user: String) async -> String {
        guard let url = buildURL() else { return "" }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setAuthHeaders(&req)
        req.timeoutInterval = 30

        guard let body = buildBody(system: system, user: user) else { return "" }
        req.httpBody = body

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return extractText(from: data)
        } catch {
            print("AI request failed: \(error)")
            return ""
        }
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
            let body: [String: Any] = [
                "model": model,
                "max_tokens": 1024,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user]
                ]
            ]
            return try? JSONSerialization.data(withJSONObject: body)

        case .gemini:
            let body: [String: Any] = [
                "system_instruction": ["parts": [["text": system]]],
                "contents": [
                    ["role": "user", "parts": [["text": user]]]
                ],
                "generationConfig": ["maxOutputTokens": 1024]
            ]
            return try? JSONSerialization.data(withJSONObject: body)
        }
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
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                print("AI API error: \(msg)")
            }
            return ""
        }
        return text
    }

    private func extractOpenAI(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        if let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let text = message["content"] as? String {
            return text
        }
        if let err = json["error"] as? [String: Any],
           let msg = err["message"] as? String {
            print("AI API error: \(msg)")
        }
        return ""
    }

    private func extractGemini(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                print("AI API error: \(msg)")
            }
            return ""
        }
        return text
    }
}

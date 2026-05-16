import Foundation

struct AiClient {
    let apiKey: String
    let endpoint: String
    let model: String

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct Request: Codable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
        }
    }

    struct Response: Codable {
        struct Content: Codable {
            let text: String?
        }
        struct ErrorInfo: Codable {
            let message: String?
        }
        let content: [Content]?
        let error: ErrorInfo?
    }

    func chat(system: String, user: String) async -> String {
        let request = Request(
            model: model,
            maxTokens: 1024,
            system: system,
            messages: [Message(role: "user", content: user)]
        )

        guard let url = URL(string: endpoint) else { return "" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 30

        guard let body = try? JSONEncoder().encode(request) else { return "" }
        req.httpBody = body

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(Response.self, from: data)
            if let text = resp.content?.first?.text { return text }
            if let err = resp.error?.message {
                print("AI API error: \(err)")
            }
        } catch {
            print("AI request failed: \(error)")
        }
        return ""
    }
}

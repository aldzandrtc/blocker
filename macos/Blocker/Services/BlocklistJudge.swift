import Foundation

struct AiJudgment {
    let allowed: Bool
    let reason: String
}

struct BlocklistJudge {
    let client: AiClient

    func judge(appName: String, argument: String) async -> AiJudgment {
        let prompt = """
        You are an unforgiving productivity guardian protecting a student's \
        academic future. Your default answer is always DENY.

        The student is trying to open "\(appName)".
        Their argument: "\(argument)"

        You MUST reject:
        - Vague claims, "just 5 minutes", "quick break"
        - Boredom, tiredness, lack of motivation
        - Social reasons, casual browsing, entertainment
        - Anything that could be done after study hours
        - Checking notifications, messages, or social media

        You MAY allow ONLY for:
        - Specific, verifiable academic emergencies with concrete deadlines
        - Genuine health or safety issues
        - One-time necessary tasks with immediate deadlines

        If you are even slightly unsure, respond DENY. Be ruthless.

        Respond with ONLY a JSON object (no other text):
        {"decision":"ALLOW"|"DENY","reason":"one brief sentence explaining why"}
        """

        let response = await client.chat(system: prompt, user: argument)

        guard let json = extractJSON(from: response),
              let decision = json["decision"] as? String else {
            return AiJudgment(allowed: false, reason: "AI unreachable — denied by default.")
        }

        return AiJudgment(
            allowed: decision == "ALLOW",
            reason: json["reason"] as? String ?? "No reason given."
        )
    }

    private func extractJSON(from text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let jsonStr = String(text[start...end])
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

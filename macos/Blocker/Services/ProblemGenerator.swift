import Foundation

struct GeneratedProblem {
    let problem: String
    let answer: String
    let answerType: String // numeric, expression, mc
    let tolerance: Double
    let topic: String
}

struct VerificationResult {
    let correct: Bool
    let explanation: String
}

struct ProblemGenerator {
    let client: AiClient
    let store: SettingsStore

    // MARK: - Generate

    func generate() async -> GeneratedProblem {
        let prompt = buildGenerationPrompt()
        let response = await client.chat(system: prompt,
            user: "Generate a problem now based on the weighting guidance above.")

        guard let json = extractJSON(from: response) else {
            return GeneratedProblem(problem: "Error generating problem.",
                                    answer: "", answerType: "numeric",
                                    tolerance: 0, topic: "error")
        }

        return GeneratedProblem(
            problem: json["problem"] as? String ?? "Error.",
            answer: json["answer"] as? String ?? "",
            answerType: json["answer_type"] as? String ?? "numeric",
            tolerance: json["tolerance"] as? Double ?? 0.001,
            topic: json["topic"] as? String ?? "general"
        )
    }

    // MARK: - Verify

    func verify(problem: GeneratedProblem, studentAnswer: String) async -> VerificationResult {
        let prompt = """
        Verify this student answer.

        Problem: \(problem.problem)
        Expected answer: \(problem.answer)
        Answer type: \(problem.answerType)
        Tolerance: \(problem.tolerance)

        Student's answer: \(studentAnswer)

        Accept equivalent forms and reasonable rounding. Be strict but fair.
        Respond with ONLY a JSON object:
        {"correct":true|false,"explanation":"brief one-line explanation"}
        """

        let response = await client.chat(system: prompt, user: studentAnswer)

        guard let json = extractJSON(from: response) else {
            return VerificationResult(correct: false, explanation: "Could not verify.")
        }

        return VerificationResult(
            correct: json["correct"] as? Bool ?? false,
            explanation: json["explanation"] as? String ?? ""
        )
    }

    // MARK: - Prompt Building

    private func buildGenerationPrompt() -> String {
        let profile = store.profile
        var prompt = """
        You are an academic problem generator. Generate ONE challenging problem.

        STUDENT PROFILE:
        - Level: \(profile.difficultyLevel)
        - Subjects: \(profile.subjects.joined(separator: ", "))
        """

        if !profile.currentFocus.isEmpty {
            prompt += "\n- Current focus: \(profile.currentFocus)"
        }

        prompt += "\n\nWEIGHTING:\n"
        prompt += weightingDescription()
        prompt += """

        Problem should take 3-5 minutes. Use LaTeX within $$ for math.
        Respond with ONLY a JSON object:
        {"problem":"...","answer":"...","answer_type":"numeric|expression|mc",
         "tolerance":0.001,"topic":"specific topic"}
        """
        return prompt
    }

    private func weightingDescription() -> String {
        let profile = store.profile
        let history = store.problemHistory
        var desc = ""

        var examNear = false
        for exam in profile.exams {
            let days = exam.daysUntil()
            if days >= 0 && days <= 21 {
                examNear = true
                desc += "- EXAM: \(exam.subject) in \(days) days → 70% weight\n"
            }
        }
        if !examNear {
            desc += "- No exams within 3 weeks → even mix\n"
        }

        for record in history where record.total > 0 {
            let pct = Int(record.accuracy * 100)
            desc += "- \(record.topic): \(pct)% (\(record.correct)/\(record.total))"
            if pct < 50 { desc += " ← WEAK" }
            desc += "\n"
        }
        if history.isEmpty {
            desc += "- No history yet → broad coverage\n"
        }
        return desc
    }

    private func extractJSON(from text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let jsonStr = String(text[start...end])
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

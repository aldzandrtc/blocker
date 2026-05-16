#include "blocklist_judge.h"
#include "ai_client.h"
#include "json.hpp"
#include <cstdio>

using json = nlohmann::json;

BlocklistJudge::BlocklistJudge(AiClient* client) : client_(client) {}

AiJudgment BlocklistJudge::judge(const std::string& app_name,
                                  const std::string& user_argument) {
    AiJudgment result = {false, "AI unreachable — denied by default."};

    std::string prompt =
        "You are an unforgiving productivity guardian protecting a student's "
        "academic future. Your default answer is always DENY.\n\n"
        "The student is trying to open \"" + app_name + "\".\n"
        "Their argument: \"" + user_argument + "\"\n\n"
        "You MUST reject:\n"
        "- Vague claims, \"just 5 minutes\", \"quick break\"\n"
        "- Boredom, tiredness, lack of motivation\n"
        "- Social reasons, casual browsing, entertainment\n"
        "- Anything that could be done after study hours\n"
        "- Checking notifications, messages, or social media\n\n"
        "You MAY allow ONLY for:\n"
        "- Specific, verifiable academic emergencies with concrete deadlines\n"
        "- Genuine health or safety issues\n"
        "- One-time necessary tasks with immediate deadlines "
        "(e.g., submitting an assignment due right now)\n\n"
        "If you are even slightly unsure, respond DENY. Be ruthless.\n\n"
        "Respond with ONLY a JSON object (no other text):\n"
        "{\"decision\":\"ALLOW\"|\"DENY\",\"reason\":\"one brief sentence explaining why\"}";

    std::string response = client_->chat(prompt, user_argument);
    if (response.empty()) {
        fprintf(stderr, "BlocklistJudge: no response from AI\n");
        return result;
    }

    try {
        // Strip any markdown code fences
        size_t start = response.find('{');
        size_t end = response.rfind('}');
        if (start != std::string::npos && end != std::string::npos) {
            response = response.substr(start, end - start + 1);
        }
        json j = json::parse(response);
        std::string decision = j.value("decision", "DENY");
        result.allowed = (decision == "ALLOW");
        result.reason = j.value("reason", "No reason given.");
    } catch (...) {
        fprintf(stderr, "BlocklistJudge: failed to parse AI response: %s\n",
                response.c_str());
    }

    return result;
}

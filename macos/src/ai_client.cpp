#include "ai_client.h"
#include "json.hpp"
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <unistd.h>

using json = nlohmann::json;

AiClient::AiClient(const std::string& api_key,
                   const std::string& endpoint,
                   const std::string& model)
    : api_key_(api_key), endpoint_(endpoint), model_(model) {}

std::string AiClient::escape_json(const std::string& s) {
    std::string out;
    for (char c : s) {
        switch (c) {
        case '"':  out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:   out += c;
        }
    }
    return out;
}

std::string AiClient::read_file(const std::string& path) {
    std::ifstream f(path);
    if (!f) return "";
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

std::string AiClient::chat(const std::string& system_prompt,
                            const std::string& user_prompt) {
    // Build request JSON
    json req;
    req["model"] = model_;
    req["max_tokens"] = 1024;
    req["system"] = system_prompt;
    req["messages"] = json::array({
        {{"role", "user"}, {"content", user_prompt}}
    });

    // Write to temp file to avoid shell escaping issues
    std::string tmpfile = "/tmp/blocker_ai_" + std::to_string(getpid()) + ".json";
    {
        std::ofstream f(tmpfile);
        if (!f) return "";
        f << req.dump();
    }

    // Build curl command
    std::string cmd = "curl -s -m 30 "
                      "-H \"Content-Type: application/json\" "
                      "-H \"x-api-key: " + api_key_ + "\" "
                      "-H \"anthropic-version: 2023-06-01\" "
                      "-d @" + tmpfile + " "
                      "\"" + endpoint_ + "\"";

    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        std::remove(tmpfile.c_str());
        return "";
    }

    std::string response;
    char buf[4096];
    while (fgets(buf, sizeof(buf), pipe)) {
        response += buf;
    }
    int rc = pclose(pipe);
    std::remove(tmpfile.c_str());

    if (rc != 0 || response.empty()) return "";

    // Parse Anthropic API response
    try {
        json resp = json::parse(response);
        if (resp.contains("content") && resp["content"].is_array()
            && !resp["content"].empty()) {
            auto& content = resp["content"][0];
            if (content.contains("text"))
                return content["text"].get<std::string>();
        }
        // Error response
        if (resp.contains("error")) {
            fprintf(stderr, "AI API error: %s\n",
                    resp["error"].value("message", "unknown").c_str());
        }
    } catch (...) {
        fprintf(stderr, "Failed to parse AI response\n");
    }
    return "";
}

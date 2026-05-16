#pragma once
#include <string>

class AiClient {
public:
    AiClient(const std::string& api_key,
             const std::string& endpoint,
             const std::string& model);

    // Send a chat request, returns the text content of the response.
    // Returns empty string on failure.
    std::string chat(const std::string& system_prompt,
                     const std::string& user_prompt);

private:
    std::string api_key_;
    std::string endpoint_;
    std::string model_;

    static std::string escape_json(const std::string& s);
    static std::string read_file(const std::string& path);
};

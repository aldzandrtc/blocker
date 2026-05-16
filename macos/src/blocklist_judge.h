#pragma once
#include <string>

struct AiJudgment {
    bool allowed;
    std::string reason;
};

class BlocklistJudge {
public:
    BlocklistJudge(class AiClient* client);

    // Ask the AI to judge whether the user's argument is sufficient.
    AiJudgment judge(const std::string& app_name,
                     const std::string& user_argument);

private:
    AiClient* client_;
};

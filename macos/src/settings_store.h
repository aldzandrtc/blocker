#pragma once
#include <string>
#include <vector>
#include <ctime>
#include "json.hpp"

using json = nlohmann::json;

struct Exam {
    std::string subject;
    std::string date; // YYYY-MM-DD
};

struct StudentProfile {
    std::vector<std::string> subjects;
    std::string current_focus;
    std::vector<Exam> exams;
    std::string difficulty_level = "college";
};

struct BlockedApp {
    std::string id;
    std::string bundle_id;
    std::string display_name;
    bool enabled = true;
};

struct ProblemRecord {
    std::string topic;
    int correct = 0;
    int incorrect = 0;
    std::string last_asked;
};

struct ApiConfig {
    std::string api_key;
    std::string endpoint = "https://api.anthropic.com/v1/messages";
    std::string model = "claude-sonnet-4-6";
};

class SettingsStore {
public:
    SettingsStore();

    ApiConfig api_config() const;
    void set_api_config(const ApiConfig& c);
    bool has_api_key() const;

    StudentProfile profile() const;
    void set_profile(const StudentProfile& p);

    std::vector<BlockedApp> blocklist() const;
    void add_to_blocklist(const std::string& bundle_id, const std::string& display_name);
    void remove_from_blocklist(const std::string& bundle_id);
    bool is_on_blocklist(const std::string& bundle_id) const;

    std::vector<ProblemRecord> problem_history() const;
    void record_problem(const std::string& topic, bool correct);

    void save();

private:
    void load();
    static std::string settings_path();

    json data_;
};

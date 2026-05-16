#pragma once
#include <string>
#include <vector>
#include <map>
#include <ctime>
#include "settings_store.h"
#include "workspace_bridge.h"
#include "ai_client.h"
#include "blocklist_judge.h"
#include "problem_generator.h"

class AppBlocker {
public:
    AppBlocker(SettingsStore* settings);
    ~AppBlocker();

    // Start monitoring and blocking. Returns 0 on success.
    int start();

    // Stop monitoring.
    void stop();

    // Called by workspace bridge when an app launches.
    void on_app_launched(const AppInfo& info);

private:
    void handle_blocklist_app(const AppInfo& info);
    void handle_regular_app(const AppInfo& info);
    void startup_sweep();

    bool is_rate_limited(const std::string& bundle_id);
    void record_denial(const std::string& bundle_id);
    bool is_session_allowed(const std::string& bundle_id);
    void add_session_allowlist(const std::string& bundle_id);

    SettingsStore* settings_;
    AiClient* ai_client_;
    BlocklistJudge* judge_;
    ProblemGenerator* generator_;
    WorkspaceBridge* bridge_;

    std::vector<std::string> session_allowlist_;
    std::map<std::string, time_t> denial_times_;

    bool running_;
};

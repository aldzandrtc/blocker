#include "app_blocker.h"
#include <cstdio>
#include <unistd.h>

static AppBlocker* g_instance = nullptr;

static void launch_callback(const AppInfo* info, void* /*context*/) {
    if (g_instance) g_instance->on_app_launched(*info);
}

AppBlocker::AppBlocker(SettingsStore* settings)
    : settings_(settings)
    , ai_client_(nullptr)
    , judge_(nullptr)
    , generator_(nullptr)
    , bridge_(nullptr)
    , running_(false)
{
    g_instance = this;
}

AppBlocker::~AppBlocker() {
    stop();
    g_instance = nullptr;
}

int AppBlocker::start() {
    if (running_) return 0;
    if (!settings_->has_api_key()) {
        fprintf(stderr, "blockerd: no API key configured. Run 'blocker setup'.\n");
        return -1;
    }

    auto cfg = settings_->api_config();
    ai_client_ = new AiClient(cfg.api_key, cfg.endpoint, cfg.model);
    judge_ = new BlocklistJudge(ai_client_);
    generator_ = new ProblemGenerator(ai_client_, settings_);

    bridge_ = bridge_create();
    if (!bridge_) return -1;

    if (bridge_start_monitoring(bridge_, launch_callback, nullptr) != 0) {
        fprintf(stderr, "blockerd: failed to start monitoring\n");
        return -1;
    }

    fprintf(stderr, "blockerd: started monitoring app launches\n");
    running_ = true;

    // Sweep already-running apps
    startup_sweep();

    return 0;
}

void AppBlocker::stop() {
    if (!running_) return;

    if (bridge_) {
        bridge_stop_monitoring(bridge_);
        bridge_destroy(bridge_);
        bridge_ = nullptr;
    }

    delete judge_;
    delete generator_;
    delete ai_client_;
    judge_ = nullptr;
    generator_ = nullptr;
    ai_client_ = nullptr;
    running_ = false;

    fprintf(stderr, "blockerd: stopped\n");
}

void AppBlocker::on_app_launched(const AppInfo& info) {
    std::string bundle_id(info.bundle_id ? info.bundle_id : "");
    int pid = info.pid;
    std::string name(info.display_name ? info.display_name : bundle_id);

    // Skip self
    if (pid == getpid()) return;

    // Skip system processes
    if (bundle_id.empty()) return;

    // Already allowed this session?
    if (is_session_allowed(bundle_id)) return;

    // Rate limited?
    if (is_rate_limited(bundle_id)) {
        fprintf(stderr, "blockerd: auto-denying %s (rate limited)\n",
                bundle_id.c_str());
        bridge_kill_app(pid);
        return;
    }

    // Freeze the app immediately
    bridge_suspend_app(pid);

    // Route to appropriate gatekeeper
    if (settings_->is_on_blocklist(bundle_id)) {
        handle_blocklist_app(info);
    } else {
        handle_regular_app(info);
    }
}

void AppBlocker::handle_blocklist_app(const AppInfo& info) {
    std::string name = info.display_name ? info.display_name :
                       (info.bundle_id ? info.bundle_id : "Unknown");

    char* argument = bridge_show_judge_dialog(name.c_str());

    if (!argument) {
        // User cancelled
        bridge_kill_app(info.pid);
        record_denial(info.bundle_id ? info.bundle_id : "");
        fprintf(stderr, "blockerd: %s cancelled judge dialog — denied\n",
                name.c_str());
        return;
    }

    std::string arg_str(argument);
    free(argument);

    AiJudgment judgment = judge_->judge(name, arg_str);

    if (judgment.allowed) {
        fprintf(stderr, "blockerd: ALLOW %s — %s\n", name.c_str(),
                judgment.reason.c_str());
        bridge_resume_app(info.pid);
        add_session_allowlist(info.bundle_id ? info.bundle_id : "");
    } else {
        fprintf(stderr, "blockerd: DENY %s — %s\n", name.c_str(),
                judgment.reason.c_str());
        bridge_kill_app(info.pid);
        record_denial(info.bundle_id ? info.bundle_id : "");
    }
}

void AppBlocker::handle_regular_app(const AppInfo& info) {
    std::string name = info.display_name ? info.display_name :
                       (info.bundle_id ? info.bundle_id : "Unknown");
    std::string bundle_id = info.bundle_id ? info.bundle_id : "";

    GeneratedProblem prob = generator_->generate();

    if (prob.problem.empty() || prob.problem.find("Error") == 0) {
        fprintf(stderr, "blockerd: problem generation failed for %s, denying\n",
                name.c_str());
        bridge_kill_app(info.pid);
        record_denial(bundle_id);
        return;
    }

    fprintf(stderr, "blockerd: generated problem for %s (topic: %s)\n",
            name.c_str(), prob.topic.c_str());

    char* answer = bridge_show_problem_dialog(prob.problem.c_str(), 300);

    if (!answer) {
        // Timed out or cancelled
        bridge_kill_app(info.pid);
        record_denial(bundle_id);
        settings_->record_problem(prob.topic, false);
        fprintf(stderr, "blockerd: %s timed out/cancelled — denied\n",
                name.c_str());
        return;
    }

    std::string ans_str(answer);
    free(answer);

    VerificationResult vr = generator_->verify(prob, ans_str);
    settings_->record_problem(prob.topic, vr.correct);

    if (vr.correct) {
        fprintf(stderr, "blockerd: CORRECT %s — allowed (%s)\n",
                name.c_str(), vr.explanation.c_str());
        bridge_resume_app(info.pid);
        add_session_allowlist(bundle_id);
    } else {
        fprintf(stderr, "blockerd: WRONG %s — denied (%s)\n",
                name.c_str(), vr.explanation.c_str());
        bridge_kill_app(info.pid);
        record_denial(bundle_id);
    }
}

void AppBlocker::startup_sweep() {
    AppInfo* apps = nullptr;
    int count = bridge_get_running_apps(&apps);
    if (!apps || count <= 0) return;

    for (int i = 0; i < count; i++) {
        std::string bundle_id = apps[i].bundle_id ? apps[i].bundle_id : "";
        if (bundle_id.empty()) continue;
        if (apps[i].pid == getpid()) continue;

        if (settings_->is_on_blocklist(bundle_id)) {
            fprintf(stderr, "blockerd: startup sweep — killing %s (%s)\n",
                    apps[i].display_name ? apps[i].display_name : bundle_id.c_str(),
                    bundle_id.c_str());
            bridge_kill_app(apps[i].pid);
        }
    }

    bridge_free_app_list(apps, count);
}

bool AppBlocker::is_rate_limited(const std::string& bundle_id) {
    auto it = denial_times_.find(bundle_id);
    if (it == denial_times_.end()) return false;
    // 5-minute cooldown
    return (time(nullptr) - it->second) < 300;
}

void AppBlocker::record_denial(const std::string& bundle_id) {
    denial_times_[bundle_id] = time(nullptr);
}

bool AppBlocker::is_session_allowed(const std::string& bundle_id) {
    for (const auto& id : session_allowlist_) {
        if (id == bundle_id) return true;
    }
    return false;
}

void AppBlocker::add_session_allowlist(const std::string& bundle_id) {
    if (!is_session_allowed(bundle_id))
        session_allowlist_.push_back(bundle_id);
}

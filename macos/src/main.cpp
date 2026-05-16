#include "settings_store.h"
#include <iostream>
#include <cstring>
#include <cstdlib>
#include <unistd.h>

#ifdef __APPLE__
#include <pwd.h>
#endif

static const char* USAGE = R"(blocker — AI-powered app blocker for macOS students

Usage:
  blocker setup                  Interactive setup (API key, subjects, exams)
  blocker config                 Show current configuration
  blocker blocklist              Show strict blocklist
  blocker blocklist add <id> [name]  Add app to strict blocklist
  blocker blocklist remove <id>      Remove app from blocklist
  blocker history [topic]        Show problem history
  blocker exams                  Show upcoming exams
  blocker profile                Show academic profile
  blocker start                  Start the blocker daemon
  blocker stop                   Stop the blocker daemon
  blocker status                 Check daemon status
)";

static std::string prompt(const char* q, const std::string& def = "") {
    std::cout << q;
    if (!def.empty()) std::cout << " [" << def << "]";
    std::cout << ": ";
    std::string line;
    std::getline(std::cin, line);
    return line.empty() ? def : line;
}

static void cmd_setup(SettingsStore& s) {
    std::cout << "=== Blocker Setup ===\n\n";

    std::cout << "API key (Anthropic or compatible): ";
    std::string key;
    std::getline(std::cin, key);
    if (key.empty()) {
        std::cout << "Setup cancelled.\n";
        return;
    }

    std::string endpoint = prompt("API endpoint",
        "https://api.anthropic.com/v1/messages");
    std::string model = prompt("Model", "claude-sonnet-4-6");

    ApiConfig cfg;
    cfg.api_key = key;
    cfg.endpoint = endpoint;
    cfg.model = model;
    s.set_api_config(cfg);

    std::cout << "\n--- Academic Profile ---\n";
    std::cout << "Enter subjects, one per line (empty line to finish):\n";
    std::vector<std::string> subjects;
    while (true) {
        std::string sub;
        std::getline(std::cin, sub);
        if (sub.empty()) break;
        subjects.push_back(sub);
    }

    std::string focus = prompt("Current focus subject (leave blank if none)");

    std::cout << "Enter upcoming exams (YYYY-MM-DD Subject), "
              << "one per line (empty line to finish):\n";
    std::vector<Exam> exams;
    while (true) {
        std::string line;
        std::getline(std::cin, line);
        if (line.empty()) break;
        // Parse: YYYY-MM-DD Subject
        if (line.length() >= 11) {
            Exam e;
            e.date = line.substr(0, 10);
            e.subject = line.substr(11);
            exams.push_back(e);
        }
    }

    std::string level = prompt("Difficulty level", "college");

    StudentProfile prof;
    prof.subjects = subjects;
    prof.current_focus = focus;
    prof.exams = exams;
    prof.difficulty_level = level;
    s.set_profile(prof);

    std::cout << "\nSetup complete. Run 'blocker start' to begin.\n";
}

static void cmd_config(SettingsStore& s) {
    auto cfg = s.api_config();
    std::cout << "API endpoint: " << cfg.endpoint << "\n";
    std::cout << "Model:        " << cfg.model << "\n";
    std::cout << "API key:      ";
    if (cfg.api_key.empty()) {
        std::cout << "(not set)\n";
    } else {
        std::cout << cfg.api_key.substr(0, 8) << "...\n";
    }
}

static void cmd_blocklist_list(SettingsStore& s) {
    auto apps = s.blocklist();
    if (apps.empty()) {
        std::cout << "Blocklist is empty. No apps receive AI scrutiny.\n";
        return;
    }
    std::cout << "Strict Blocklist (AI judge):\n";
    for (const auto& a : apps) {
        std::cout << "  " << a.display_name << " (" << a.bundle_id << ")\n";
    }
}

static void cmd_blocklist_add(SettingsStore& s, int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "Usage: blocker blocklist add <bundle-id> [display-name]\n";
        return;
    }
    std::string bundle_id = argv[3];
    std::string display_name = argc >= 5 ? argv[4] : bundle_id;
    s.add_to_blocklist(bundle_id, display_name);
    std::cout << "Added " << display_name << " (" << bundle_id
              << ") to strict blocklist.\n";
}

static void cmd_blocklist_remove(SettingsStore& s, int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "Usage: blocker blocklist remove <bundle-id>\n";
        return;
    }
    s.remove_from_blocklist(argv[3]);
    std::cout << "Removed " << argv[3] << " from blocklist.\n";
}

static void cmd_history(SettingsStore& s, int argc, char** argv) {
    auto history = s.problem_history();
    if (history.empty()) {
        std::cout << "No problem history yet.\n";
        return;
    }

    std::string filter = argc >= 4 ? argv[3] : "";
    std::cout << "Problem History:\n";
    for (const auto& r : history) {
        if (!filter.empty() && r.topic != filter) continue;
        int total = r.correct + r.incorrect;
        int pct = total > 0 ? (r.correct * 100) / total : 0;
        std::cout << "  " << r.topic << ": " << pct << "% ("
                  << r.correct << "/" << total
                  << ") last: " << r.last_asked;
        if (pct < 50) std::cout << " ← weak";
        std::cout << "\n";
    }
}

static void cmd_exams(SettingsStore& s) {
    auto profile = s.profile();
    if (profile.exams.empty()) {
        std::cout << "No exams configured. Run 'blocker setup'.\n";
        return;
    }
    std::cout << "Upcoming exams:\n";
    time_t now = time(nullptr);
    for (const auto& e : profile.exams) {
        struct tm tm = {};
        tm.tm_year = std::stoi(e.date.substr(0, 4)) - 1900;
        tm.tm_mon  = std::stoi(e.date.substr(5, 2)) - 1;
        tm.tm_mday = std::stoi(e.date.substr(8, 2));
        time_t et = mktime(&tm);
        int days = (int)(std::difftime(et, now) / 86400.0);
        std::cout << "  " << e.subject << " — " << e.date
                  << " (" << days << " days)\n";
    }
}

static void cmd_profile(SettingsStore& s) {
    auto p = s.profile();
    std::cout << "Subjects: ";
    for (size_t i = 0; i < p.subjects.size(); i++) {
        if (i) std::cout << ", ";
        std::cout << p.subjects[i];
    }
    std::cout << "\nFocus: " << (p.current_focus.empty() ? "(none)" : p.current_focus)
              << "\nLevel: " << p.difficulty_level << "\n";
    cmd_exams(s);
}

static std::string plist_path() {
    const char* home = getenv("HOME");
#ifdef __APPLE__
    if (!home) {
        struct passwd* pw = getpwuid(getuid());
        home = pw ? pw->pw_dir : "/tmp";
    }
#endif
    return std::string(home) + "/Library/LaunchAgents/com.blocker.blockerd.plist";
}

static void cmd_start(SettingsStore& s) {
    if (!s.has_api_key()) {
        std::cerr << "No API key configured. Run 'blocker setup' first.\n";
        return;
    }

    // Install plist if not present
    std::string plist = plist_path();
    std::string cmd = "launchctl load \"" + plist + "\" 2>&1";
    int rc = system(cmd.c_str());
    if (rc != 0) {
        std::cerr << "Failed to load LaunchAgent. Is blockerd installed? "
                  << "Run 'make install' first.\n";
        return;
    }
    std::cout << "Blocker daemon started.\n";
}

static void cmd_stop() {
    std::string plist = plist_path();
    std::string cmd = "launchctl unload \"" + plist + "\" 2>&1";
    system(cmd.c_str());
    std::cout << "Blocker daemon stopped.\n";
}

static void cmd_status() {
    std::string cmd = "launchctl list | grep com.blocker.blockerd 2>&1";
    int rc = system(cmd.c_str());
    if (rc != 0) {
        std::cout << "Blocker daemon is not running.\n";
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cout << USAGE;
        return 0;
    }

    SettingsStore settings;
    std::string subcmd = argv[1];

    if (subcmd == "setup") {
        cmd_setup(settings);
    } else if (subcmd == "config") {
        cmd_config(settings);
    } else if (subcmd == "blocklist") {
        if (argc < 3) {
            cmd_blocklist_list(settings);
        } else {
            std::string action = argv[2];
            if (action == "add") cmd_blocklist_add(settings, argc, argv);
            else if (action == "remove") cmd_blocklist_remove(settings, argc, argv);
            else if (action == "list") cmd_blocklist_list(settings);
            else std::cerr << "Unknown blocklist action: " << action << "\n";
        }
    } else if (subcmd == "history") {
        cmd_history(settings, argc, argv);
    } else if (subcmd == "exams") {
        cmd_exams(settings);
    } else if (subcmd == "profile") {
        cmd_profile(settings);
    } else if (subcmd == "start") {
        cmd_start(settings);
    } else if (subcmd == "stop") {
        cmd_stop();
    } else if (subcmd == "status") {
        cmd_status();
    } else if (subcmd == "help" || subcmd == "--help" || subcmd == "-h") {
        std::cout << USAGE;
    } else {
        std::cerr << "Unknown command: " << subcmd << "\n" << USAGE;
        return 1;
    }

    return 0;
}

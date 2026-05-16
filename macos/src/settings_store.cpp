#include "settings_store.h"
#include <fstream>
#include <cstdlib>
#include <sys/stat.h>

#ifdef __APPLE__
#include <pwd.h>
#include <unistd.h>
#endif

static std::string config_dir() {
    const char* home = getenv("HOME");
    if (!home) {
#ifdef __APPLE__
        struct passwd* pw = getpwuid(getuid());
        home = pw ? pw->pw_dir : "/tmp";
#else
        home = "/tmp";
#endif
    }
    std::string dir = std::string(home) + "/.config/blocker";
    mkdir(dir.c_str(), 0755);
    return dir;
}

std::string SettingsStore::settings_path() {
    return config_dir() + "/settings.json";
}

SettingsStore::SettingsStore() {
    load();
}

void SettingsStore::load() {
    std::ifstream f(settings_path());
    if (!f.is_open()) {
        data_ = json::object();
        return;
    }
    try {
        data_ = json::parse(f);
    } catch (...) {
        data_ = json::object();
    }
}

void SettingsStore::save() {
    std::string path = settings_path();
    std::ofstream f(path);
    if (f.is_open()) {
        f << data_.dump(2);
    }
}

ApiConfig SettingsStore::api_config() const {
    ApiConfig c;
    if (data_.contains("api_key"))
        c.api_key = data_["api_key"].get<std::string>();
    if (data_.contains("api_endpoint"))
        c.endpoint = data_["api_endpoint"].get<std::string>();
    if (data_.contains("model"))
        c.model = data_["model"].get<std::string>();
    return c;
}

void SettingsStore::set_api_config(const ApiConfig& c) {
    data_["api_key"] = c.api_key;
    data_["api_endpoint"] = c.endpoint;
    data_["model"] = c.model;
    save();
}

bool SettingsStore::has_api_key() const {
    return data_.contains("api_key") && !data_["api_key"].get<std::string>().empty();
}

StudentProfile SettingsStore::profile() const {
    StudentProfile p;
    if (!data_.contains("profile")) return p;
    const auto& pr = data_["profile"];
    if (pr.contains("subjects"))
        for (const auto& s : pr["subjects"])
            p.subjects.push_back(s.get<std::string>());
    if (pr.contains("current_focus"))
        p.current_focus = pr["current_focus"].get<std::string>();
    if (pr.contains("exams"))
        for (const auto& e : pr["exams"])
            p.exams.push_back({e["subject"].get<std::string>(),
                               e["date"].get<std::string>()});
    if (pr.contains("difficulty_level"))
        p.difficulty_level = pr["difficulty_level"].get<std::string>();
    return p;
}

void SettingsStore::set_profile(const StudentProfile& p) {
    json pr;
    pr["subjects"] = p.subjects;
    pr["current_focus"] = p.current_focus;
    json exams = json::array();
    for (const auto& e : p.exams)
        exams.push_back({{"subject", e.subject}, {"date", e.date}});
    pr["exams"] = exams;
    pr["difficulty_level"] = p.difficulty_level;
    data_["profile"] = pr;
    save();
}

std::vector<BlockedApp> SettingsStore::blocklist() const {
    std::vector<BlockedApp> apps;
    if (!data_.contains("blocklist")) return apps;
    for (const auto& a : data_["blocklist"]) {
        apps.push_back({
            a.value("id", ""),
            a.value("bundle_id", ""),
            a.value("display_name", ""),
            a.value("enabled", true)
        });
    }
    return apps;
}

void SettingsStore::add_to_blocklist(const std::string& bundle_id,
                                      const std::string& display_name) {
    if (!data_.contains("blocklist"))
        data_["blocklist"] = json::array();

    // Check duplicate
    for (auto& a : data_["blocklist"]) {
        if (a["bundle_id"] == bundle_id) return;
    }

    // Generate a simple unique ID
    std::string id = std::to_string(std::time(nullptr)) + "_" + bundle_id;

    json entry;
    entry["id"] = id;
    entry["bundle_id"] = bundle_id;
    entry["display_name"] = display_name;
    entry["enabled"] = true;
    data_["blocklist"].push_back(entry);
    save();
}

void SettingsStore::remove_from_blocklist(const std::string& bundle_id) {
    if (!data_.contains("blocklist")) return;
    auto& arr = data_["blocklist"];
    for (auto it = arr.begin(); it != arr.end(); ++it) {
        if ((*it)["bundle_id"] == bundle_id) {
            arr.erase(it);
            save();
            return;
        }
    }
}

bool SettingsStore::is_on_blocklist(const std::string& bundle_id) const {
    if (!data_.contains("blocklist")) return false;
    for (const auto& a : data_["blocklist"]) {
        if (a.value("bundle_id", "") == bundle_id && a.value("enabled", true))
            return true;
    }
    return false;
}

std::vector<ProblemRecord> SettingsStore::problem_history() const {
    std::vector<ProblemRecord> records;
    if (!data_.contains("problem_history")) return records;
    for (const auto& r : data_["problem_history"]) {
        records.push_back({
            r.value("topic", ""),
            r.value("correct", 0),
            r.value("incorrect", 0),
            r.value("last_asked", "")
        });
    }
    return records;
}

void SettingsStore::record_problem(const std::string& topic, bool correct) {
    if (!data_.contains("problem_history"))
        data_["problem_history"] = json::array();

    auto& arr = data_["problem_history"];
    for (auto& r : arr) {
        if (r["topic"] == topic) {
            if (correct) r["correct"] = r.value("correct", 0) + 1;
            else r["incorrect"] = r.value("incorrect", 0) + 1;
            // Today's date
            time_t now = time(nullptr);
            char buf[16];
            strftime(buf, sizeof(buf), "%Y-%m-%d", localtime(&now));
            r["last_asked"] = buf;
            save();
            return;
        }
    }

    // New topic
    time_t now = time(nullptr);
    char buf[16];
    strftime(buf, sizeof(buf), "%Y-%m-%d", localtime(&now));
    json entry;
    entry["topic"] = topic;
    entry["correct"] = correct ? 1 : 0;
    entry["incorrect"] = correct ? 0 : 1;
    entry["last_asked"] = buf;
    arr.push_back(entry);
    save();
}

#include "problem_generator.h"
#include "ai_client.h"
#include "json.hpp"
#include <cstdio>
#include <ctime>
#include <cmath>

using json = nlohmann::json;

ProblemGenerator::ProblemGenerator(AiClient* client, SettingsStore* settings)
    : client_(client), settings_(settings) {}

static int days_until(const std::string& date_str) {
    struct tm target = {};
    if (date_str.length() != 10) return 999;
    target.tm_year = std::stoi(date_str.substr(0, 4)) - 1900;
    target.tm_mon  = std::stoi(date_str.substr(5, 2)) - 1;
    target.tm_mday = std::stoi(date_str.substr(8, 2));
    time_t target_t = mktime(&target);
    time_t now = time(nullptr);
    return (int)std::ceil(std::difftime(target_t, now) / 86400.0);
}

std::string ProblemGenerator::subject_weighting_description() {
    auto profile = settings_->profile();
    auto history = settings_->problem_history();

    std::string desc;

    // Check upcoming exams
    bool exam_near = false;
    for (const auto& e : profile.exams) {
        int d = days_until(e.date);
        if (d >= 0 && d <= 21) {
            exam_near = true;
            desc += "- EXAM IMMINENT: " + e.subject + " (" + std::to_string(d)
                    + " days away) — 70% weight\n";
        }
    }

    if (!exam_near) {
        desc += "- No exams within 3 weeks — even mix across subjects\n";
    }

    // Current focus
    if (!profile.current_focus.empty()) {
        desc += "- Current focus subject: " + profile.current_focus + "\n";
    }

    // Topic performance
    if (!history.empty()) {
        desc += "- Per-topic performance:\n";
        for (const auto& r : history) {
            int total = r.correct + r.incorrect;
            if (total > 0) {
                int pct = (r.correct * 100) / total;
                desc += "  " + r.topic + ": " + std::to_string(pct) + "% ("
                        + std::to_string(r.correct) + "/" + std::to_string(total)
                        + ")";
                if (pct < 50) desc += " ← WEAK, prioritize";
                desc += "\n";
            }
        }
    }

    return desc;
}

std::string ProblemGenerator::build_generation_prompt() {
    auto profile = settings_->profile();

    std::string prompt =
        "You are an academic problem generator for a student. "
        "Generate ONE challenging problem.\n\n"
        "STUDENT PROFILE:\n"
        "- Level: " + profile.difficulty_level + "\n"
        "- Subjects: ";
    for (size_t i = 0; i < profile.subjects.size(); i++) {
        if (i > 0) prompt += ", ";
        prompt += profile.subjects[i];
    }
    prompt += "\n\nWEIGHTING GUIDANCE:\n" + subject_weighting_description() + "\n"
        "The problem should take 3-5 minutes to solve. Make it genuinely "
        "challenging — no trivial questions. Use LaTeX math notation within "
        "$$ delimiters where appropriate.\n\n"
        "Respond with ONLY a JSON object (no other text):\n"
        "{\"problem\":\"the problem text\","
        "\"answer\":\"the correct answer\","
        "\"answer_type\":\"numeric|expression|mc\","
        "\"tolerance\":0.001,"
        "\"topic\":\"specific topic name\"}\n\n"
        "For answer_type 'numeric', provide a number and set tolerance appropriately. "
        "For 'expression', provide the answer in standard mathematical notation. "
        "For 'mc', include the letter of the correct choice as the answer.";

    return prompt;
}

GeneratedProblem ProblemGenerator::generate() {
    GeneratedProblem gp;
    gp.answer_type = "numeric";
    gp.tolerance = 0.001;

    std::string prompt = build_generation_prompt();
    std::string response = client_->chat(prompt,
        "Generate a problem now based on the weighting guidance above.");

    if (response.empty()) {
        gp.problem = "Error: Could not generate a problem. Try again.";
        gp.answer = "0";
        return gp;
    }

    try {
        // Strip markdown code fences
        size_t start = response.find('{');
        size_t end = response.rfind('}');
        if (start != std::string::npos && end != std::string::npos) {
            response = response.substr(start, end - start + 1);
        }
        json j = json::parse(response);
        gp.problem = j.value("problem", "Error parsing problem");
        gp.answer = j.value("answer", "");
        gp.answer_type = j.value("answer_type", "numeric");
        gp.tolerance = j.value("tolerance", 0.001);
        gp.topic = j.value("topic", "general");
    } catch (...) {
        fprintf(stderr, "ProblemGenerator: failed to parse generation response\n");
        gp.problem = "Error: Could not generate a problem. Try again.";
        gp.answer = "0";
    }

    return gp;
}

VerificationResult ProblemGenerator::verify(const GeneratedProblem& problem,
                                              const std::string& student_answer) {
    VerificationResult vr = {false, "Could not verify answer."};

    std::string prompt =
        "You are verifying a student's answer to a problem YOU generated.\n\n"
        "Problem: " + problem.problem + "\n\n"
        "Expected answer: " + problem.answer + "\n"
        "Answer type: " + problem.answer_type + "\n"
        "Tolerance: " + std::to_string(problem.tolerance) + "\n\n"
        "Student's answer: " + student_answer + "\n\n"
        "Accept equivalent mathematical forms, reasonable rounding within "
        "tolerance, and minor formatting differences (spaces, capitalization). "
        "For expressions, accept equivalent algebraic forms. "
        "Be strict but fair — don't accept clearly wrong answers, "
        "but don't penalize trivial formatting differences.\n\n"
        "Respond with ONLY a JSON object (no other text):\n"
        "{\"correct\":true|false,\"explanation\":\"brief one-line explanation\"}";

    std::string response = client_->chat(prompt, student_answer);
    if (response.empty()) return vr;

    try {
        size_t start = response.find('{');
        size_t end = response.rfind('}');
        if (start != std::string::npos && end != std::string::npos) {
            response = response.substr(start, end - start + 1);
        }
        json j = json::parse(response);
        vr.correct = j.value("correct", false);
        vr.explanation = j.value("explanation", "No explanation given.");
    } catch (...) {
        fprintf(stderr, "ProblemGenerator: failed to parse verification response\n");
    }

    return vr;
}

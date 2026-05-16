#pragma once
#include <string>
#include "settings_store.h"

struct GeneratedProblem {
    std::string problem;
    std::string answer;
    std::string answer_type; // numeric, expression, mc
    double tolerance;
    std::string topic;
};

struct VerificationResult {
    bool correct;
    std::string explanation;
};

class ProblemGenerator {
public:
    ProblemGenerator(class AiClient* client, SettingsStore* settings);

    // Generate a problem based on student profile and history.
    GeneratedProblem generate();

    // Verify the student's answer against the correct one.
    VerificationResult verify(const GeneratedProblem& problem,
                              const std::string& student_answer);

private:
    std::string build_generation_prompt();
    std::string subject_weighting_description();

    AiClient* client_;
    SettingsStore* settings_;
};

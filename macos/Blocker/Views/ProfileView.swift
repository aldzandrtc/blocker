import SwiftUI

struct ProfileView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var newSubject = ""
    @State private var examSubject = ""
    @State private var examDate = Date()
    @State private var focusInput = ""
    @State private var difficultyInput = "college"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Academic Profile")
                    .font(.title2)
                    .padding(.horizontal)

                // Subjects
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Add subject", text: $newSubject)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                let trimmed = newSubject.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    settings.profile.subjects.append(trimmed)
                                    newSubject = ""
                                    settings.save()
                                }
                            }
                            .disabled(newSubject.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        ForEach(settings.profile.subjects, id: \.self) { subject in
                            HStack {
                                Text(subject)
                                Spacer()
                                Button {
                                    settings.profile.subjects.removeAll { $0 == subject }
                                    settings.save()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } label: {
                    Label("Subjects", systemImage: "book.fill")
                }
                .padding(.horizontal)

                // Current focus
                GroupBox {
                    Picker("Focus", selection: $focusInput) {
                        Text("None").tag("")
                        ForEach(settings.profile.subjects, id: \.self) { subject in
                            Text(subject).tag(subject)
                        }
                    }
                    .onAppear { focusInput = settings.profile.currentFocus }
                    .onChange(of: focusInput) { _, value in
                        settings.profile.currentFocus = value
                        settings.save()
                    }
                } label: {
                    Label("Current Focus", systemImage: "target")
                }
                .padding(.horizontal)

                // Exams
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Subject", text: $examSubject)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            DatePicker("Date", selection: $examDate, displayedComponents: .date)
                                .labelsHidden()
                            Spacer()
                            Button("Add Exam") {
                                let trimmed = examSubject.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    let df = DateFormatter()
                                    df.dateFormat = "yyyy-MM-dd"
                                    let exam = Exam(subject: trimmed,
                                                    date: df.string(from: examDate))
                                    settings.profile.exams.append(exam)
                                    examSubject = ""
                                    settings.save()
                                }
                            }
                            .disabled(examSubject.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        ForEach(settings.profile.exams) { exam in
                            HStack {
                                Text(exam.subject)
                                Spacer()
                                Text(exam.date)
                                    .foregroundStyle(.secondary)
                                Text("(\(exam.daysUntil())d)")
                                    .foregroundStyle(exam.daysUntil() <= 3 ? .red : .secondary)
                                Button {
                                    settings.profile.exams.removeAll { $0.id == exam.id }
                                    settings.save()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } label: {
                    Label("Exams", systemImage: "calendar.badge.clock")
                }
                .padding(.horizontal)

                // Difficulty
                GroupBox {
                    Picker("Level", selection: $difficultyInput) {
                        Text("High School").tag("high-school")
                        Text("College").tag("college")
                        Text("Graduate").tag("graduate")
                    }
                    .pickerStyle(.segmented)
                    .onAppear { difficultyInput = settings.profile.difficultyLevel }
                    .onChange(of: difficultyInput) { _, value in
                        settings.profile.difficultyLevel = value
                        settings.save()
                    }
                } label: {
                    Label("Difficulty Level", systemImage: "graduationcap.fill")
                }
                .padding(.horizontal)

                // Unblock & cooldown durations
                GroupBox {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Unblock:")
                            Slider(value: Binding(
                                get: { Double(settings.profile.unblockDurationMinutes) },
                                set: { settings.profile.unblockDurationMinutes = Int($0); settings.save() }
                            ), in: 5...120, step: 5)
                            Text("\(settings.profile.unblockDurationMinutes)m")
                                .frame(width: 40, alignment: .trailing)
                        }
                        HStack {
                            Text("Cooldown:")
                            Slider(value: Binding(
                                get: { Double(settings.profile.cooldownMinutes) },
                                set: { settings.profile.cooldownMinutes = Int($0); settings.save() }
                            ), in: 1...30, step: 1)
                            Text("\(settings.profile.cooldownMinutes)m")
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                } label: {
                    Label("Timing", systemImage: "timer")
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.vertical)
        }
    }
}

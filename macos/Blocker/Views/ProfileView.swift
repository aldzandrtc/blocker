import SwiftUI

struct ProfileView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var newSubject = ""
    @State private var examSubject = ""
    @State private var examDate = Date()
    @State private var showingTimingSheet = false

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.block) {
                subjects
                focus(binding: $settings.profile.currentFocus)
                exams
                difficulty(binding: $settings.profile.difficultyLevel)
                limits
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 14)
        }
        .sheet(isPresented: $showingTimingSheet) {
            TimingChangeSheet(settings: settings, isPresented: $showingTimingSheet)
        }
    }

    // MARK: - Subjects

    private var subjects: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Subjects", trailing: "problems are drawn from these")

            Card {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 8) {
                        TextField("Add a subject", text: $newSubject)
                            .softField()
                            .onSubmit(addSubject)
                        Button("Add", action: addSubject)
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(newSubject.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if settings.profile.subjects.isEmpty {
                        Text("Without subjects the AI has to guess what you study.")
                            .font(Face.body(11))
                            .foregroundStyle(Palette.tertiary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(settings.profile.subjects, id: \.self) { subject in
                                HStack(spacing: 5) {
                                    Text(subject)
                                        .font(Face.body(11.5, .medium))
                                    Button {
                                        removeSubject(subject)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Palette.tertiary)
                                    .accessibilityLabel("Remove \(subject)")
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Palette.accent.opacity(0.12)))
                                .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
            }
        }
    }

    private func addSubject() {
        let trimmed = newSubject.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !settings.profile.subjects.contains(trimmed) else { return }
        settings.profile.subjects.append(trimmed)
        newSubject = ""
        settings.save()
    }

    private func removeSubject(_ subject: String) {
        settings.profile.subjects.removeAll { $0 == subject }
        if settings.profile.currentFocus == subject {
            settings.profile.currentFocus = ""
        }
        settings.save()
    }

    // MARK: - Focus

    private func focus(binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Current focus")
            Card {
                Picker("", selection: binding) {
                    Text("No preference").tag("")
                    ForEach(settings.profile.subjects, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .onChange(of: settings.profile.currentFocus) { _, _ in settings.save() }
            }
        }
    }

    // MARK: - Exams

    private var exams: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Exams", trailing: "one within 3 weeks dominates")

            Card {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 8) {
                        TextField("Subject", text: $examSubject)
                            .softField()
                            .frame(width: 128)
                        DatePicker("", selection: $examDate, displayedComponents: .date)
                            .labelsHidden()
                            .controlSize(.small)
                        Spacer(minLength: 0)
                        Button("Add", action: addExam)
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(examSubject.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if settings.profile.exams.isEmpty {
                        Text("An exam within three weeks pulls problems toward that subject.")
                            .font(Face.body(11))
                            .foregroundStyle(Palette.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 0) {
                            let sorted = settings.profile.exams.sorted { $0.daysUntil() < $1.daysUntil() }
                            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, exam in
                                let days = exam.daysUntil()
                                HStack(spacing: 9) {
                                    Text(exam.subject)
                                        .font(Face.body(12, .medium))
                                        .lineLimit(1)
                                    Spacer(minLength: 6)
                                    Text(exam.date)
                                        .font(Face.body(10.5))
                                        .foregroundStyle(Palette.tertiary)
                                    Chip(text: days < 0 ? "Past" : (days == 0 ? "Today" : "\(days)d"),
                                         tint: days < 0 ? Palette.tertiary
                                             : (days <= 3 ? Palette.danger : Palette.accent),
                                         filled: days >= 0 && days <= 3)
                                    Button {
                                        settings.profile.exams.removeAll { $0.id == exam.id }
                                        settings.save()
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(IconButtonStyle())
                                    .accessibilityLabel("Remove \(exam.subject)")
                                }
                                .padding(.vertical, 6)

                                if index < sorted.count - 1 {
                                    Divider().overlay(Palette.strokeFaint)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func addExam() {
        let trimmed = examSubject.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        settings.profile.exams.append(
            Exam(subject: trimmed, date: Exam.dateFormatter.string(from: examDate))
        )
        examSubject = ""
        settings.save()
    }

    // MARK: - Difficulty

    private func difficulty(binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Level")
            Card {
                Picker("", selection: binding) {
                    Text("High school").tag("high-school")
                    Text("College").tag("college")
                    Text("Graduate").tag("graduate")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: settings.profile.difficultyLevel) { _, _ in settings.save() }
            }
        }
    }

    // MARK: - Limits (judge-gated)

    private var limits: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Limits", trailing: "loosening needs the judge")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        limit(value: settings.profile.unblockDurationMinutes,
                              label: "Unblock window", caption: "how long it stays open",
                              icon: "lock.open.fill")
                        Divider().frame(height: 40).overlay(Palette.strokeFaint)
                        limit(value: settings.profile.cooldownMinutes,
                              label: "Cooldown", caption: "wait after a failed try",
                              icon: "hourglass")
                    }

                    Text("Tightening applies immediately. Loosening has to be argued — that's the moment self-control usually fails.")
                        .font(Face.body(10.5))
                        .foregroundStyle(Palette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Change limits") { showingTimingSheet = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private func limit(value: Int, label: String, caption: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.accent.opacity(0.8))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(Face.display(21, .bold))
                Text("min")
                    .font(Face.body(10.5))
                    .foregroundStyle(Palette.tertiary)
            }
            Text(label)
                .font(Face.body(11, .medium))
                .foregroundStyle(Palette.secondary)
            Text(caption)
                .font(Face.body(10))
                .foregroundStyle(Palette.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

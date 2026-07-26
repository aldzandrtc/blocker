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
                standingOrders
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 16)
        }
        .sheet(isPresented: $showingTimingSheet) {
            TimingChangeSheet(settings: settings, isPresented: $showingTimingSheet)
        }
    }

    // MARK: - Subjects

    private var subjects: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "Subjects")

            HStack(alignment: .bottom, spacing: 10) {
                TextField("add a subject", text: $newSubject)
                    .ruledField()
                    .onSubmit(addSubject)
                Button("Add", action: addSubject)
                    .buttonStyle(OutlineButtonStyle(tint: Palette.ink))
                    .disabled(newSubject.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if settings.profile.subjects.isEmpty {
                Text("Problems are drawn from your subjects.")
                    .font(Face.body(11.5))
                    .foregroundStyle(Palette.faint)
            } else {
                FlowLayout(spacing: 7) {
                    ForEach(settings.profile.subjects, id: \.self) { subject in
                        HStack(spacing: 6) {
                            Text(subject)
                                .font(Face.body(11.5))
                            Button {
                                settings.profile.subjects.removeAll { $0 == subject }
                                if settings.profile.currentFocus == subject {
                                    settings.profile.currentFocus = ""
                                }
                                settings.save()
                            } label: {
                                Text("×").font(Face.clerk(11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.faint)
                            .accessibilityLabel("Remove \(subject)")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
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

    // MARK: - Focus

    private func focus(binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionRule(title: "Current focus")
            Picker("", selection: binding) {
                Text("no preference").tag("")
                ForEach(settings.profile.subjects, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .onChange(of: settings.profile.currentFocus) { _, _ in settings.save() }
        }
    }

    // MARK: - Exams

    private var exams: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "Examinations")

            HStack(alignment: .bottom, spacing: 10) {
                TextField("subject", text: $examSubject)
                    .ruledField()
                    .frame(width: 130)
                DatePicker("", selection: $examDate, displayedComponents: .date)
                    .labelsHidden()
                    .controlSize(.small)
                Spacer()
                Button("Add", action: addExam)
                    .buttonStyle(OutlineButtonStyle(tint: Palette.ink))
                    .disabled(examSubject.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if settings.profile.exams.isEmpty {
                Text("An exam within three weeks pulls problems toward that subject.")
                    .font(Face.body(11.5))
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    let sorted = settings.profile.exams.sorted { $0.daysUntil() < $1.daysUntil() }
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, exam in
                        let days = exam.daysUntil()
                        HStack(spacing: 10) {
                            Text(exam.subject)
                                .font(Face.body(12))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(exam.date)
                                .font(Face.clerk(9))
                                .foregroundStyle(Palette.faint)
                            Text(days < 0 ? "PAST" : (days == 0 ? "TODAY" : "\(days)D"))
                                .font(Face.clerk(9, .semibold))
                                .foregroundStyle(days < 0 ? Palette.faint
                                                 : (days <= 3 ? Palette.seal : Palette.muted))
                                .frame(width: 44, alignment: .trailing)
                            Button {
                                settings.profile.exams.removeAll { $0.id == exam.id }
                                settings.save()
                            } label: {
                                Text("×").font(Face.clerk(11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.faint)
                            .accessibilityLabel("Remove \(exam.subject)")
                        }
                        .padding(.vertical, 6)
                        if index < sorted.count - 1 { Rule(color: Palette.ruleFaint) }
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
        VStack(alignment: .leading, spacing: 9) {
            SectionRule(title: "Level")
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

    // MARK: - Standing orders (judge-gated)

    private var standingOrders: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionRule(title: "Standing orders", trailing: "sealed")

            HStack(alignment: .top, spacing: 0) {
                order(value: settings.profile.unblockDurationMinutes,
                      label: "unblock window", caption: "stays open")
                Rectangle().fill(Palette.ruleFaint).frame(width: 1, height: 38)
                order(value: settings.profile.cooldownMinutes,
                      label: "cooldown", caption: "between tries")
            }

            Text("Tightening takes effect at once. Loosening must be argued before the judge.")
                .font(Face.body(11))
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)

            Button("Move to amend") { showingTimingSheet = true }
                .buttonStyle(OutlineButtonStyle(tint: Palette.ink))
        }
    }

    private func order(value: Int, label: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(Face.display(24, .medium))
                Text("min")
                    .font(Face.clerk(9))
                    .foregroundStyle(Palette.faint)
            }
            Text(label.uppercased())
                .font(Face.clerk(8, .semibold))
                .tracking(1.2)
                .foregroundStyle(Palette.muted)
            Text(caption)
                .font(Face.body(10))
                .foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 12)
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

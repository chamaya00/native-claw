import SwiftUI
import SwiftData
import MemoryKit
import SkillsKit

/// The skills inbox + library (§Phase 6). The assistant proposes reusable, multi-step
/// skills it noticed; the user approves, edits, runs, or dismisses them here. This is where
/// "propose-then-approve" and "self-improvement without code" are made real: a skill never
/// runs or reaches Siri/Shortcuts until approved, a dismissal is a durable negative signal,
/// and an assistant-proposed revision is applied only if the user accepts it.
struct SkillsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Skill.createdAt, order: .reverse) private var skills: [Skill]

    @State private var editing: Skill?
    @State private var runResult: SkillRunPresentation?
    @State private var runningSkillID: UUID?

    private var suggested: [Skill] {
        skills.filter { $0.status == SkillStatus.suggested.rawValue }
    }
    private var approved: [Skill] {
        skills.filter { $0.status == SkillStatus.approved.rawValue }
    }

    var body: some View {
        Group {
            if suggested.isEmpty && approved.isEmpty {
                emptyState
            } else {
                List {
                    if !suggested.isEmpty { suggestedSection }
                    if !approved.isEmpty { approvedSection }
                    infoFooter
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editing) { skill in
            SkillEditSheet(skill: skill) { name, summary, recipe in
                SkillStore.update(skill, name: name, summary: summary, recipe: recipe, context: modelContext)
                if skill.status == SkillStatus.approved.rawValue { SkillSpotlightIndexer.index(skill) }
            }
        }
        .sheet(item: $runResult) { presentation in
            SkillRunResultSheet(presentation: presentation)
        }
    }

    // MARK: - Suggested (awaiting approval)

    private var suggestedSection: some View {
        Section {
            ForEach(suggested) { skill in
                SuggestedSkillRow(
                    skill: skill,
                    onApprove: { approve(skill) },
                    onEdit: { editing = skill },
                    onDismiss: { dismiss(skill) }
                )
            }
        } header: {
            Label("Suggested (\(suggested.count))", systemImage: "tray.full")
        } footer: {
            Text("Claw noticed these repeated patterns. Approve to save a skill — only approved skills run or appear in Siri & Shortcuts.")
        }
    }

    // MARK: - Approved (the library)

    private var approvedSection: some View {
        Section("Your skills") {
            ForEach(approved) { skill in
                ApprovedSkillRow(
                    skill: skill,
                    isRunning: runningSkillID == skill.id,
                    onRun: { run(skill) },
                    onEdit: { editing = skill },
                    onAcceptRevision: { acceptRevision(skill) },
                    onRejectRevision: { SkillStore.rejectRevision(for: skill, context: modelContext) }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { dismiss(skill) } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var infoFooter: some View {
        Section {
            EmptyView()
        } footer: {
            Label(
                "Skills are recipes of built-in actions (calendar, memory, briefing) — never code. Running one only reads your data or repeats actions you've already approved.",
                systemImage: "checkmark.shield"
            )
            .font(.caption2)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wand.and.rays")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No skills yet")
                .font(.title3.weight(.semibold))
            Text("As you chat, Claw notices multi-step routines worth saving — like a Monday review — and proposes them here. Approve one and you can run it any time, or from Siri and Shortcuts.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Actions

    private func approve(_ skill: Skill) {
        SkillStore.approve(skill, context: modelContext)
        SkillSpotlightIndexer.index(skill)
    }

    private func dismiss(_ skill: Skill) {
        SkillSpotlightIndexer.remove(id: skill.id)
        SkillStore.dismiss(skill, context: modelContext)
    }

    private func acceptRevision(_ skill: Skill) {
        SkillStore.acceptRevision(for: skill, context: modelContext)
        SkillSpotlightIndexer.index(skill)
    }

    private func run(_ skill: Skill) {
        guard runningSkillID == nil else { return }
        runningSkillID = skill.id
        let container = modelContext.container
        let name = skill.name
        Task {
            let result = await SkillRunner(container: container).run(skill)
            await MainActor.run {
                runningSkillID = nil
                runResult = SkillRunPresentation(title: name, body: result.text, succeeded: result.succeeded)
            }
        }
    }
}

// MARK: - Rows

private struct SuggestedSkillRow: View {
    let skill: Skill
    let onApprove: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skill.name).font(.subheadline.weight(.medium))
            if !skill.summary.isEmpty {
                Text(skill.summary).font(.caption).foregroundStyle(.secondary)
            }
            if !skill.rationale.isEmpty {
                Label(skill.rationale, systemImage: "sparkles")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            RecipeChips(recipe: skill.intentRecipe)

            HStack(spacing: 12) {
                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil").font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onDismiss) {
                    Label("Dismiss", systemImage: "xmark").font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

private struct ApprovedSkillRow: View {
    let skill: Skill
    let isRunning: Bool
    let onRun: () -> Void
    let onEdit: () -> Void
    let onAcceptRevision: () -> Void
    let onRejectRevision: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(skill.name).font(.subheadline.weight(.medium))
                Spacer()
                if skill.runCount > 0 {
                    Text("\(Int((skill.successRate * 100).rounded()))% · \(skill.runCount) run\(skill.runCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if !skill.summary.isEmpty {
                Text(skill.summary).font(.caption).foregroundStyle(.secondary)
            }
            RecipeChips(recipe: skill.intentRecipe)

            // Assistant-proposed self-improvement, applied only if the user accepts it.
            if let revision = skill.proposedRevision {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Suggested update", systemImage: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.purple)
                    Text(revision).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Accept", action: onAcceptRevision)
                            .buttonStyle(.borderedProminent).controlSize(.mini)
                        Button("Keep current", action: onRejectRevision)
                            .buttonStyle(.bordered).controlSize(.mini)
                    }
                }
                .padding(8)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Button(action: onRun) {
                    if isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Run", systemImage: "play.fill").font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRunning)

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil").font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

/// The recipe rendered as a row of action chips, so the user always sees exactly what a
/// skill will do — the transparency that makes a declarative routine trustworthy.
private struct RecipeChips: View {
    let recipe: [String]

    var body: some View {
        let actions = SkillAction.recipe(from: recipe)
        if !actions.isEmpty {
            ViewThatFits(in: .horizontal) {
                chips(actions)
                ScrollView(.horizontal, showsIndicators: false) { chips(actions) }
            }
        }
    }

    private func chips(_ actions: [SkillAction]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Label(action.displayName, systemImage: action.systemImage)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground), in: Capsule())
            }
        }
    }
}

// MARK: - Run result sheet

struct SkillRunPresentation: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let succeeded: Bool
}

private struct SkillRunResultSheet: View {
    let presentation: SkillRunPresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(presentation.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle(presentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Edit sheet

private struct SkillEditSheet: View {
    let skill: Skill
    let onSave: (_ name: String, _ summary: String, _ recipe: [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var summary: String
    @State private var selected: Set<SkillAction>

    init(skill: Skill, onSave: @escaping (String, String, [String]) -> Void) {
        self.skill = skill
        self.onSave = onSave
        _name = State(initialValue: skill.name)
        _summary = State(initialValue: skill.summary)
        _selected = State(initialValue: Set(SkillAction.recipe(from: skill.intentRecipe)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Skill name", text: $name)
                }
                Section("What it does") {
                    TextField("One-line summary", text: $summary, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section {
                    ForEach(SkillAction.allCases) { action in
                        Button {
                            if selected.contains(action) { selected.remove(action) }
                            else { selected.insert(action) }
                        } label: {
                            HStack {
                                Label(action.displayName, systemImage: action.systemImage)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(action) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Steps run in order. Each is a built-in action that only reads your data or repeats something you've approved — never code.")
                }
            }
            .navigationTitle("Edit skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Preserve catalog order so a saved recipe reads predictably.
                        let recipe = SkillAction.allCases.filter { selected.contains($0) }.map(\.rawValue)
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines),
                               summary.trimmingCharacters(in: .whitespacesAndNewlines),
                               recipe)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty)
                }
            }
        }
    }
}

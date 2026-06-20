import SwiftUI
import SwiftData
import UIKit
import MemoryKit

/// "What you know about me" (§Phase 3). The user can see, edit, approve, and delete
/// everything the assistant remembers, review facts the curation pass proposed, export
/// the lot, and wipe it entirely. Legible, user-owned memory is the moat — and the
/// privacy guarantee only holds if revoking it is this direct.
struct MemoryBrowserView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \MemoryNote.importanceScore, order: .reverse) private var allMemories: [MemoryNote]

    @State private var expandedID: UUID?
    @State private var searchText: String = ""
    @State private var editing: MemoryNote?
    @State private var showForgetConfirm = false

    private var approved: [MemoryNote] { allMemories.filter { $0.isUserApproved } }
    private var pending: [MemoryNote] {
        allMemories.filter { !$0.isUserApproved }.sorted { $0.createdAt > $1.createdAt }
    }

    private var filtered: [MemoryNote] {
        guard !searchText.isEmpty else { return approved }
        let lower = searchText.lowercased()
        return approved.filter {
            $0.title.lowercased().contains(lower)
            || $0.summary.lowercased().contains(lower)
            || $0.topics.contains { $0.lowercased().contains(lower) }
        }
    }

    var body: some View {
        Group {
            if approved.isEmpty && pending.isEmpty {
                emptyState
            } else {
                List {
                    if !pending.isEmpty { reviewSection }
                    if !approved.isEmpty { memorySection }
                    syncFooter
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Search memories")
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: exportMarkdown) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(approved.isEmpty)
                    Divider()
                    Button(role: .destructive) { showForgetConfirm = true } label: {
                        Label("Forget everything", systemImage: "trash")
                    }
                    .disabled(allMemories.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editing) { note in
            MemoryEditSheet(note: note) { title, summary, topics, importance in
                updateNote(note, title: title, summary: summary, topics: topics,
                           importance: importance, context: modelContext)
            }
        }
        .alert("Forget everything?", isPresented: $showForgetConfirm) {
            Button("Forget", role: .destructive) {
                forgetAllMemory(context: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every fact Claw remembers, on this device and across your synced devices. This can't be undone.")
        }
    }

    // MARK: - Review inbox (curated candidates awaiting approval)

    private var reviewSection: some View {
        Section {
            ForEach(pending) { note in
                ReviewRow(
                    note: note,
                    onApprove: { approveNote(note, context: modelContext) },
                    onReject: { deleteNote(note, context: modelContext) }
                )
            }
        } header: {
            Label("Review (\(pending.count))", systemImage: "tray.full")
        } footer: {
            Text("Claw distilled these from your conversations. Approve to remember, or dismiss.")
        }
    }

    // MARK: - Approved memories

    private var memorySection: some View {
        Section("Remembered") {
            ForEach(filtered) { note in
                MemoryNoteRow(
                    note: note,
                    isExpanded: expandedID == note.id,
                    onToggle: {
                        withAnimation(.spring(duration: 0.3)) {
                            expandedID = expandedID == note.id ? nil : note.id
                        }
                    }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteNote(note, context: modelContext)
                    } label: { Label("Delete", systemImage: "trash") }
                    Button { editing = note } label: { Label("Edit", systemImage: "pencil") }
                        .tint(.blue)
                }
            }
        }
    }

    private var syncFooter: some View {
        Section {
            EmptyView()
        } footer: {
            Label(
                MemoryContainer.isCloudSyncing
                    ? "Synced privately across your devices via iCloud."
                    : "Stored on this device. iCloud sync is unavailable on this build.",
                systemImage: MemoryContainer.isCloudSyncing ? "checkmark.icloud" : "icloud.slash"
            )
            .font(.caption2)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No memories yet")
                .font(.title3.weight(.semibold))
            Text("As you chat, Claw proposes things worth remembering. Approve them here and they personalize every future conversation.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Export

    private func exportMarkdown() {
        var md = "# Claw Memory Export\n\nExported: \(Date.now.formatted())\n\n"
        for note in approved {
            md += "## \(note.title)\n\n\(note.summary)\n\n"
            if !note.topics.isEmpty {
                md += "**Topics:** \(note.topics.joined(separator: ", "))\n\n"
            }
            if let source = note.sourceLabel {
                md += "*Source: \(source)*\n\n"
            }
            md += "---\n\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claw-memory.md")
        try? md.write(to: url, atomically: true, encoding: .utf8)

        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}

// MARK: - Review Row

struct ReviewRow: View {
    let note: MemoryNote
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                if note.isSensitive {
                    Image(systemName: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(note.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            Text(note.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if note.isSensitive {
                Text("Sensitive — review carefully before approving.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: onReject) {
                    Label("Dismiss", systemImage: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edit Sheet

struct MemoryEditSheet: View {
    let note: MemoryNote
    let onSave: (_ title: String, _ summary: String, _ topics: [String], _ importance: Float) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var summary: String
    @State private var topicsText: String
    @State private var importance: Double

    init(note: MemoryNote,
         onSave: @escaping (String, String, [String], Float) -> Void) {
        self.note = note
        self.onSave = onSave
        _title = State(initialValue: note.title)
        _summary = State(initialValue: note.summary)
        _topicsText = State(initialValue: note.topics.joined(separator: ", "))
        _importance = State(initialValue: Double(note.importanceScore))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Summary") {
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Topics") {
                    TextField("Comma-separated topics", text: $topicsText)
                }
                Section("Importance") {
                    Slider(value: $importance, in: 0...1)
                    Text("\(Int(importance * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let topics = topicsText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines),
                               summary.trimmingCharacters(in: .whitespacesAndNewlines),
                               topics, Float(importance))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Memory Note Row

struct MemoryNoteRow: View {
    let note: MemoryNote
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            Button(action: onToggle) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        if !isExpanded {
                            Text(note.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        importanceBadge
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(note.summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    if !note.topics.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(note.topics, id: \.self) { topic in
                                Text(topic)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.systemGray5), in: Capsule())
                            }
                        }
                    }

                    HStack {
                        if let source = note.sourceLabel {
                            Text(source)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var importanceBadge: some View {
        let pct = Int(note.importanceScore * 100)
        return Text("\(pct)%")
            .font(.caption2.weight(.medium))
            .foregroundStyle(importanceColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(importanceColor.opacity(0.12), in: Capsule())
    }

    private var importanceColor: Color {
        switch note.importanceScore {
        case 0.8...: return .red
        case 0.6..<0.8: return .orange
        case 0.4..<0.6: return .yellow
        default: return .secondary
        }
    }
}

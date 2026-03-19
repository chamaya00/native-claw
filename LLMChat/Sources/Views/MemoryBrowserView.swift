import SwiftUI
import SwiftData

struct MemoryBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<MemoryNote> { $0.isUserApproved == true },
        sort: [SortDescriptor(\MemoryNote.importanceScore, order: .reverse),
               SortDescriptor(\MemoryNote.updatedAt, order: .reverse)]
    ) private var memories: [MemoryNote]

    @State private var expandedID: UUID?
    @State private var searchText: String = ""
    @State private var showArchived = false

    private var filtered: [MemoryNote] {
        if searchText.isEmpty { return memories }
        let lower = searchText.lowercased()
        return memories.filter {
            $0.title.lowercased().contains(lower)
            || $0.summary.lowercased().contains(lower)
            || $0.topics.contains { $0.lowercased().contains(lower) }
        }
    }

    var body: some View {
        Group {
            if memories.isEmpty {
                emptyState
            } else {
                List {
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
                    }
                    .onDelete(perform: deleteNotes)
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Search memories")
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportMarkdown) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(memories.isEmpty)
            }
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
            Text("Claw will propose memory notes during conversations. Approve them to save here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Actions

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = filtered[index]
            modelContext.delete(note)
        }
        try? modelContext.save()
    }

    private func exportMarkdown() {
        var md = "# Claw Memory Export\n\nExported: \(Date.now.formatted())\n\n"
        for note in memories {
            md += "## \(note.title)\n\n"
            md += "\(note.summary)\n\n"
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

import UIKit

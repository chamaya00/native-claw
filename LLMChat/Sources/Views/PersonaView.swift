import SwiftUI
import SwiftData

struct PersonaView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var personas: [Persona]
    let agentService: AgentService
    @State private var showReconfigure = false

    private var persona: Persona? { personas.first }

    var body: some View {
        Group {
            if let persona {
                personaDetail(persona)
            } else {
                noPersonaView
            }
        }
        .navigationTitle("Persona")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Reconfigure") { showReconfigure = true }
                    .font(.subheadline)
            }
        }
        .sheet(isPresented: $showReconfigure) {
            reconfigureSheet
        }
    }

    // MARK: - Persona Detail

    private func personaDetail(_ persona: Persona) -> some View {
        List {
            Section {
                HStack {
                    Text("◈")
                        .font(.system(size: 36))
                        .frame(width: 56, height: 56)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(persona.name)
                            .font(.title2.weight(.semibold))
                        Text("Updated \(persona.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Vibe") {
                Text(persona.vibe.isEmpty ? "Not set" : persona.vibe)
                    .font(.body)
                    .foregroundStyle(persona.vibe.isEmpty ? .secondary : .primary)
            }

            if !persona.values.isEmpty {
                Section("Values") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                        ForEach(persona.values, id: \.self) { value in
                            Text(value)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !persona.expertiseAreas.isEmpty {
                Section("Expertise Areas") {
                    ForEach(persona.expertiseAreas, id: \.self) { area in
                        Label(area, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }

            Section {
                Button("Propose update via chat", systemImage: "bubble.left.and.bubble.right") {
                    // TODO: Navigate back to chat and pre-fill a "update my persona" prompt
                }
                .foregroundStyle(Color.accentColor)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - No Persona

    private var noPersonaView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No persona configured")
                .font(.title3.weight(.semibold))
            Text("Complete onboarding to create your Claw persona.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Reconfigure Sheet

    private var reconfigureSheet: some View {
        NavigationStack {
            OnboardingView(
                agentService: agentService,
                container: modelContext.container,
                onComplete: { showReconfigure = false }
            )
            .navigationTitle("Reconfigure Claw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showReconfigure = false }
                }
            }
        }
    }
}

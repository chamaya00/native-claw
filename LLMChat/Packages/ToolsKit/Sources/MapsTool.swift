import Foundation
import MapKit
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels

/// Natural-language place lookups via MapKit's `MKLocalSearch` (read-only). Answers
/// "find a coffee shop nearby" / "where is the nearest pharmacy" without a custom backend.
struct MapLookupTool: Tool {
    static let toolName = "lookupPlace"
    let name = MapLookupTool.toolName
    let description = "Search for places, businesses, or addresses by name using Maps."

    @Generable
    struct Arguments {
        @Guide(description: "What to search for, e.g. 'coffee near downtown', 'pharmacy', a business name or address")
        var query: String
    }

    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        await onEvent(.toolStarted("Searching maps…"))
        defer { Task { await onEvent(.toolCompleted) } }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = arguments.query

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch {
            return "Maps search failed: \(error.localizedDescription)"
        }

        if response.mapItems.isEmpty {
            return "No places found for '\(arguments.query)'."
        }

        let lines = response.mapItems.prefix(5).map { item -> String in
            let name = item.name ?? "Unknown"
            let address = Self.address(for: item)
            let phone = item.phoneNumber.map { " · \($0)" } ?? ""
            return "- \(name): \(address)\(phone)"
        }
        return "Places for '\(arguments.query)':\n" + lines.joined(separator: "\n")
    }

    private static func address(for item: MKMapItem) -> String {
        let p = item.placemark
        let parts = [p.thoroughfare, p.locality, p.administrativeArea].compactMap { $0 }
        return parts.isEmpty ? "address unavailable" : parts.joined(separator: ", ")
    }
}

#endif

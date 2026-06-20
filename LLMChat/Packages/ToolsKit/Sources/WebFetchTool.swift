import Foundation
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels

/// Fetches a web page and returns its text (read-only). HTML is stripped to plain text
/// and truncated *before* it reaches the model — a full page would blow the 4K budget,
/// so we pre-digest exactly as we do for images (§Phase 2).
struct WebFetchTool: Tool {
    static let toolName = "fetchWebPage"
    let name = WebFetchTool.toolName
    let description = "Fetch a web page by URL and return its readable text content."

    private static let maxChars = 3000

    @Generable
    struct Arguments {
        @Guide(description: "The full URL to fetch, including https://")
        var url: String
    }

    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        await onEvent(.toolStarted("Fetching web page…"))
        defer { Task { await onEvent(.toolCompleted) } }

        guard let url = URL(string: arguments.url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return "That doesn't look like a valid web URL. Provide a full http(s) address."
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (compatible; ClawAssistant/1.0)", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return "Couldn't load \(url.host ?? arguments.url): \(error.localizedDescription)"
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return "The page returned HTTP \(http.statusCode)."
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let text = Self.plainText(fromHTML: html)

        if text.isEmpty {
            return "Loaded \(url.absoluteString) but found no readable text."
        }
        let body = text.count > Self.maxChars
            ? String(text.prefix(Self.maxChars)) + "…[truncated]"
            : text
        return "Content of \(url.absoluteString):\n\(body)"
    }

    /// Strip scripts/styles/tags and collapse whitespace. Deliberately lightweight —
    /// it only needs to be good enough to extract readable text on-device.
    static func plainText(fromHTML html: String) -> String {
        var s = html
        for tag in ["script", "style", "head", "noscript", "svg"] {
            // `[\s\S]*?` (not `.*?`) so the block match spans newlines.
            s = s.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(\\s*\\n\\s*){2,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#endif

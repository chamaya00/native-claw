import Foundation
import Contacts
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels

/// Looks up a contact by name (read-only — no approval needed). Returns phone/email so
/// the assistant can answer "what's Jordan's number?" without leaving the device.
struct LookupContactTool: Tool {
    static let toolName = "lookupContact"
    let name = LookupContactTool.toolName
    let description = "Look up a person in the user's Contacts by name and return their phone numbers and emails."

    @Generable
    struct Arguments {
        @Guide(description: "The name (or partial name) of the contact to find")
        var name: String
    }

    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        await onEvent(.toolStarted("Looking up contact…"))
        defer { Task { await onEvent(.toolCompleted) } }

        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else {
            return "Contacts access hasn't been granted. The user can enable it in Settings → Privacy → Contacts."
        }

        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey
        ] as [CNKeyDescriptor]

        let predicate = CNContact.predicateForContacts(matchingName: arguments.name)
        let matches = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []

        if matches.isEmpty {
            return "No contacts found matching '\(arguments.name)'."
        }

        let lines = matches.prefix(5).map { contact -> String in
            let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            let phones = contact.phoneNumbers.map { $0.value.stringValue }
            let emails = contact.emailAddresses.map { $0.value as String }
            var detail = [String]()
            if !phones.isEmpty { detail.append("phone: \(phones.joined(separator: ", "))") }
            if !emails.isEmpty { detail.append("email: \(emails.joined(separator: ", "))") }
            return "- \(fullName.isEmpty ? "(no name)" : fullName)" + (detail.isEmpty ? "" : " — \(detail.joined(separator: "; "))")
        }
        return "Contacts matching '\(arguments.name)':\n" + lines.joined(separator: "\n")
    }
}

#endif

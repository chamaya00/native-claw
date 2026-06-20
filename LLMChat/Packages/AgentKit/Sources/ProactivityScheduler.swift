import Foundation
import SwiftData
import BackgroundTasks
import UserNotifications
import MemoryKit
import os

/// Schedules and runs approved proactive routines (§Phase 5). The hard product rule, made
/// structural here: **only user-approved routines ever notify**, and a notification is the
/// only thing that reaches outside the app — suggestions stay in-app.
///
/// Uses `BGTaskScheduler` (the only native path for unattended work — best-effort, not
/// cron) for the wake-up and `UNUserNotificationCenter` for delivery. Handler registration
/// is done by the app's SwiftUI `.backgroundTask(.appRefresh:)` scene modifier, which calls
/// `handleRefresh(container:)`; this type owns submission, generation, and delivery.
public enum ProactivityScheduler {

    /// Must match the app's `BGTaskSchedulerPermittedIdentifiers` Info.plist entry and the
    /// `.backgroundTask(.appRefresh:)` id in the scene.
    public static let refreshTaskID = "com.charlesamaya.llmchat.briefing"

    private static let log = Logger(subsystem: "com.charlesamaya.llmchat", category: "Proactivity")

    // MARK: - Permissions

    /// Request notification permission. Called when the user approves their first routine —
    /// progressive permission framed by the value it unlocks, never an up-front wall (§B).
    @discardableResult
    public static func requestNotificationAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    // MARK: - Scheduling

    /// Submit the next briefing wake-up *if* at least one approved routine exists. Idempotent
    /// — safe to call on every launch/activation; resubmitting just replaces the request.
    @MainActor
    public static func scheduleIfNeeded(container: ModelContainer) {
        let context = ModelContext(container)
        guard !approvedRoutines(context: context).isEmpty else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
            return
        }
        schedule()
    }

    /// Submit a single app-refresh request for the next morning.
    public static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = nextMorning()
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Common on simulators / when Background App Refresh is off — not user-facing.
            log.debug("BGTaskScheduler submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Background execution

    /// Run the brief and deliver it, then reschedule. Invoked from the app's
    /// `.backgroundTask(.appRefresh:)` handler, so it inherits that task's expiration.
    public static func handleRefresh(container: ModelContainer) async {
        // Reschedule first so a failure below never breaks the chain.
        schedule()

        let hasRoutine = await MainActor.run {
            !approvedRoutines(context: ModelContext(container)).isEmpty
        }
        guard hasRoutine else { return }

        guard let brief = await BriefingService(container: container).generateBrief(),
              !brief.isEmpty else { return }
        await deliver(brief)
    }

    private static func deliver(_ body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your brief"
        content.body = body
        // Immediate delivery — we're already in the scheduled background window.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    // MARK: - Helpers

    /// The next 8am from now (today if it hasn't passed, otherwise tomorrow).
    private static func nextMorning(now: Date = .now) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 8
        components.minute = 0
        let today8 = calendar.date(from: components) ?? now.addingTimeInterval(3600)
        if today8 > now { return today8 }
        return calendar.date(byAdding: .day, value: 1, to: today8) ?? now.addingTimeInterval(86_400)
    }
}

import Foundation
import AgentKit

/// The initial eval set for the assistant's real tasks (§Phase 4 deliverable: "build eval
/// sets for the real assistant tasks"). Each task pins down a behaviour the on-device
/// model has to get right — extraction, summarisation, classification — which are exactly
/// what the small model is optimised for (CLAUDE.md device-scope note), so this is where
/// it should score well and where the on-device/PCC boundary first becomes visible.
public enum AssistantEvalSuite {

    public static let all: [EvalTask] = [
        EvalTask(
            id: "reminder.extract.time",
            kind: .chat,
            instructions: "You extract structured details from the user's request. Be terse. No preamble.",
            prompt: "Remind me to call the dentist tomorrow at 9am.",
            mustContain: ["dentist", "9"],
            rationale: "Extraction: the model must surface the subject and the time from a natural reminder request — the Phase-1 reminder tool depends on this."
        ),
        EvalTask(
            id: "calendar.parse.event",
            kind: .chat,
            instructions: "You extract structured details from the user's request. Be terse. No preamble.",
            prompt: "Add a lunch with Sam on Friday at noon at Cafe Roma.",
            mustContain: ["lunch", "friday", "roma"],
            rationale: "Extraction: title, day, and location from a one-line event — the Phase-2 calendar tool depends on this."
        ),
        EvalTask(
            id: "classify.sensitive",
            kind: .curation,
            instructions: "Classify whether the statement is sensitive (health, finances, relationships, precise location). Answer with the single word 'sensitive' or 'ordinary'.",
            prompt: "I started a new medication for my blood pressure this week.",
            mustContain: ["sensitive"],
            rationale: "Classification: curation must flag health facts as sensitive so they're never auto-approved (Phase-3 guardrail)."
        ),
        EvalTask(
            id: "summarize.terse",
            kind: .summarization,
            instructions: "Summarise into one short sentence of durable facts. No preamble.",
            prompt: "I'm planning a trip to Lisbon in October, I prefer window seats, and I'm vegetarian.",
            mustContain: ["lisbon"],
            rationale: "Summarisation: the ContextBudget re-seat path relies on the model condensing turns without dropping the key fact."
        ),
        EvalTask(
            id: "reasoning.multistep",
            kind: .reasoning,
            instructions: "Answer concisely. Show the final number only at the end on its own line.",
            prompt: "I have 3 meetings of 45 minutes each and a 30 minute lunch between 9am and 1pm. How many free minutes are left in that window?",
            mustContain: ["45"],
            rationale: "Reasoning: a multi-step arithmetic task — the kind that motivates PCC escalation when the on-device model is unreliable on it."
        ),
        EvalTask(
            id: "skill.plan.synthesis",
            kind: .briefing,
            instructions: """
            You turn a set of notes — calendar, priorities, a brief — into a short, prioritised \
            plan for the day. Three to five plain-text bullet points, most important first. Be \
            concrete and specific to the notes; never pad with generic advice.
            """,
            prompt: """
            Check today's calendar:
            • 10:00 AM: Dentist
            • 2:00 PM: Project review with Sam
            Review what I care about:
            • Q3 launch: ship the beta this week
            """,
            mustContain: ["dentist", "sam"],
            rationale: "Synthesis: the Phase-6 skill runner's planDay step must fold calendar + priorities into a concrete plan without dropping the day's actual items."
        )
    ]
}

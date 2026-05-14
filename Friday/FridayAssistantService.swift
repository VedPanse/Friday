//
//  FridayAssistantService.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

actor FridayAssistantService {
    private let recommendationEngine = RecommendationEngine()

    #if canImport(FoundationModels)
    private var foundationModelsResponder: FoundationModelsResponder?
    #endif

    func respond(to message: String, context: AssistantContext) async -> AssistantResponse {
        let fallbackRecommendation = recommendationEngine.recommendation(for: context)
        let memoryCandidate = MemoryCandidateExtractor.extract(from: message)

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let responder = foundationModelsResponder ?? FoundationModelsResponder()
                foundationModelsResponder = responder
                let response = try await responder.respond(
                    to: message,
                    context: context,
                    recommendation: fallbackRecommendation
                )

                return AssistantResponse(
                    message: response,
                    recommendation: fallbackRecommendation,
                    memoryCandidate: memoryCandidate,
                    usedFoundationModel: true
                )
            } catch {
                return fallbackResponse(
                    to: message,
                    context: context,
                    recommendation: fallbackRecommendation,
                    memoryCandidate: memoryCandidate
                )
            }
        }
        #endif

        return fallbackResponse(
            to: message,
            context: context,
            recommendation: fallbackRecommendation,
            memoryCandidate: memoryCandidate
        )
    }

    func recommendation(for context: AssistantContext) -> AssistantRecommendation {
        recommendationEngine.recommendation(for: context)
    }

    private func fallbackResponse(
        to message: String,
        context: AssistantContext,
        recommendation: AssistantRecommendation,
        memoryCandidate: String?
    ) -> AssistantResponse {
        let response: String
        let normalizedMessage = message.lowercased()

        if normalizedMessage.contains("what should") || normalizedMessage.contains("focus") {
            response = """
            Focus on \(recommendation.title). \(recommendation.reason) Start with this: \(recommendation.nextStep)
            """
        } else if memoryCandidate != nil {
            response = """
            I’ll remember that. For now, I recommend \(recommendation.title.lowercased()): \(recommendation.nextStep)
            """
        } else if context.calendar.upcomingEvents.isEmpty && context.mail.unreadCount == 0 {
            response = """
            I don’t see urgent calendar or inbox pressure right now. \(recommendation.nextStep)
            """
        } else {
            response = """
            I’m here to help you make the next good move. Right now: \(recommendation.title). \(recommendation.nextStep)
            """
        }

        return AssistantResponse(
            message: response,
            recommendation: recommendation,
            memoryCandidate: memoryCandidate,
            usedFoundationModel: false
        )
    }
}

private nonisolated struct RecommendationEngine {
    func recommendation(for context: AssistantContext) -> AssistantRecommendation {
        if let deadline = highPriorityDeadline(in: context) {
            return deadline
        }

        if let nextEvent = context.calendar.eventsToday.first(where: { !$0.isAllDay }) {
            return AssistantRecommendation(
                title: "Prepare for \(nextEvent.title)",
                reason: "This is the next thing on your calendar today.",
                nextStep: "Spend 20 minutes reviewing what you need before it starts.",
                durationMinutes: 20,
                priority: .normal
            )
        }

        if context.mail.unreadCount > 0 {
            return AssistantRecommendation(
                title: "Triage your inbox",
                reason: "You have \(context.mail.unreadCount) unread message\(context.mail.unreadCount == 1 ? "" : "s").",
                nextStep: "Spend 15 minutes clearing anything that needs a reply or calendar follow-up.",
                durationMinutes: 15,
                priority: .normal
            )
        }

        return .fallback
    }

    private func highPriorityDeadline(in context: AssistantContext) -> AssistantRecommendation? {
        let deadlines = context.calendar.upcomingEvents
            .filter { event in
                let title = event.title.lowercased()
                return ["exam", "midterm", "final", "quiz", "deadline"].contains { title.contains($0) }
            }
            .sorted { $0.startDate < $1.startDate }

        guard let event = deadlines.first else {
            return nil
        }

        let daysUntilEvent = Calendar.current.dateComponents([.day], from: context.now, to: event.startDate).day ?? 0
        let relevantMemories = context.memories.filter { memory in
            memory.text.lowercased().hasMeaningfulOverlap(with: event.title.lowercased())
        }

        let needsExtraTime = relevantMemories.contains { memory in
            let text = memory.text.lowercased()
            return ["bad", "weak", "nervous", "anxious", "struggle", "behind", "hard"].contains { text.contains($0) }
        }

        let duration = needsExtraTime ? 60 : 45
        let memoryReason = needsExtraTime ? " You’ve told me this area needs extra attention." : ""
        let deadlineWord = daysUntilEvent <= 0 ? "today" : "in \(daysUntilEvent) day\(daysUntilEvent == 1 ? "" : "s")"

        return AssistantRecommendation(
            title: "Study for \(event.title)",
            reason: "\(event.title) is \(deadlineWord).\(memoryReason)",
            nextStep: "Start a \(duration)-minute focused review block now.",
            durationMinutes: duration,
            priority: daysUntilEvent <= 7 ? .high : .normal
        )
    }
}

private nonisolated enum MemoryCandidateExtractor {
    static func extract(from message: String) -> String? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMessage.count >= 8 else {
            return nil
        }

        let lowercasedMessage = trimmedMessage.lowercased()
        let memorySignals = [
            "i am bad at",
            "i'm bad at",
            "i feel nervous",
            "i am nervous",
            "i'm nervous",
            "i struggle with",
            "i prefer",
            "i usually",
            "i need more time",
            "i hate",
            "i like",
        ]

        guard memorySignals.contains(where: { lowercasedMessage.contains($0) }) else {
            return nil
        }

        return trimmedMessage
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private nonisolated final class FoundationModelsResponder {
    private let model = SystemLanguageModel.default
    private lazy var session = LanguageModelSession(instructions: Self.instructions)

    func respond(
        to message: String,
        context: AssistantContext,
        recommendation: AssistantRecommendation
    ) async throws -> String {
        guard case .available = model.availability else {
            throw AssistantModelError.foundationModelUnavailable
        }

        let response = try await session.respond(to: prompt(
            message: message,
            context: context,
            recommendation: recommendation
        ))

        return response.content
    }

    private func prompt(
        message: String,
        context: AssistantContext,
        recommendation: AssistantRecommendation
    ) -> String {
        """
        Current date: \(context.now.formatted(date: .abbreviated, time: .shortened))

        Current recommendation:
        - Focus: \(recommendation.title)
        - Reason: \(recommendation.reason)
        - Next step: \(recommendation.nextStep)

        Calendar today:
        \(context.calendar.eventsToday.map { "- \($0.title) at \($0.startDate.formatted(date: .omitted, time: .shortened))" }.joined(separator: "\n"))

        Upcoming calendar:
        \(context.calendar.upcomingEvents.prefix(8).map { "- \($0.title) on \($0.startDate.formatted(date: .abbreviated, time: .shortened))" }.joined(separator: "\n"))

        Mail:
        - Unread: \(context.mail.unreadCount)
        - Recent: \(context.mail.recentSubjects.prefix(5).joined(separator: "; "))

        Memory:
        \(context.memories.prefix(12).map { "- \($0.text)" }.joined(separator: "\n"))

        User asks:
        \(message)
        """
    }

    private static let instructions = """
    You are Friday, a personal AI assistant for the user. Your job is to help the user achieve their goals.
    You may use calendar summaries, mail summaries, and stored memories. Distinguish known facts from guesses.
    Give one clear recommendation for what to focus on right now. Be concise, specific, and practical.
    Do not claim to have read full emails unless the context includes the relevant details.
    Do not automatically change the user’s calendar or tasks.
    """
}
#endif

private nonisolated enum AssistantModelError: Error {
    case foundationModelUnavailable
}

private nonisolated extension String {
    func hasMeaningfulOverlap(with other: String) -> Bool {
        let ownTokens = Set(significantTokens)
        let otherTokens = Set(other.significantTokens)
        return !ownTokens.intersection(otherTokens).isEmpty
    }

    var significantTokens: [String] {
        components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { $0.count >= 3 }
    }
}

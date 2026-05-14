//
//  FridayAssistantDomain.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import Foundation

nonisolated struct AssistantContext: Equatable {
    let now: Date
    let calendar: CalendarContext
    let mail: MailContext
    let memories: [MemoryRecord]
}

nonisolated struct CalendarContext: Equatable {
    let eventsToday: [CalendarEvent]
    let upcomingEvents: [CalendarEvent]
    let statusMessage: String?

    static let loading = CalendarContext(eventsToday: [], upcomingEvents: [], statusMessage: "Checking calendar access")

    static func unavailable(_ message: String) -> CalendarContext {
        CalendarContext(eventsToday: [], upcomingEvents: [], statusMessage: message)
    }
}

nonisolated struct CalendarEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool

    init(id: UUID = UUID(), title: String, startDate: Date, endDate: Date, isAllDay: Bool) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
    }
}

nonisolated struct MailContext: Equatable {
    let unreadCount: Int
    let latestSubject: String?
    let recentSubjects: [String]
    let statusMessage: String?

    static let loading = MailContext(
        unreadCount: 0,
        latestSubject: nil,
        recentSubjects: [],
        statusMessage: "Checking Mail access"
    )

    static func unavailable(_ message: String) -> MailContext {
        MailContext(unreadCount: 0, latestSubject: nil, recentSubjects: [], statusMessage: message)
    }
}

nonisolated struct MemoryRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date
    let lastSeenAt: Date
    let source: MemorySource

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        lastSeenAt: Date = Date(),
        source: MemorySource
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.source = source
    }
}

nonisolated enum MemorySource: String, Codable {
    case conversation
    case inferred
}

nonisolated struct AssistantRecommendation: Equatable {
    let title: String
    let reason: String
    let nextStep: String
    let durationMinutes: Int
    let priority: RecommendationPriority

    static let fallback = AssistantRecommendation(
        title: "Plan the next useful step",
        reason: "Friday does not have enough urgent calendar or mail context yet.",
        nextStep: "Ask Friday what you should focus on, or add upcoming deadlines to your calendar.",
        durationMinutes: 20,
        priority: .normal
    )
}

nonisolated enum RecommendationPriority: String, Codable, Equatable {
    case low
    case normal
    case high
}

nonisolated struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

nonisolated enum ChatRole: Equatable {
    case user
    case friday
}

nonisolated struct AssistantResponse: Equatable {
    let message: String
    let recommendation: AssistantRecommendation
    let memoryCandidate: String?
    let usedFoundationModel: Bool
}

//
//  HomeViewModel.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var prompt = ""
    @Published private(set) var calendarContext = CalendarContext.loading
    @Published private(set) var mailContext = MailContext.loading
    @Published private(set) var memories: [MemoryRecord] = []
    @Published private(set) var messages: [ChatMessage] = [
        ChatMessage(
            role: .friday,
            text: "I’m Friday. I’ll help you decide what to focus on and remember what matters."
        ),
    ]
    @Published private(set) var recommendation = AssistantRecommendation.fallback
    @Published private(set) var isResponding = false
    @Published private(set) var modelStatusText = "Preparing Friday"

    private let calendarReader: CalendarContextReading
    private let mailReader: MailContextReading
    private let memoryStore: FridayMemoryStore
    private let assistantService: FridayAssistantService
    private let notificationService: AppNotificationService

    private var lastNotificationDate: Date?
    private var lastNotifiedRecommendationTitle: String?

    init(
        calendarReader: CalendarContextReading = EventKitCalendarContextReader(),
        mailReader: MailContextReading = MailAppleScriptContextReader(),
        memoryStore: FridayMemoryStore = .shared,
        assistantService: FridayAssistantService = FridayAssistantService(),
        notificationService: AppNotificationService = .shared
    ) {
        self.calendarReader = calendarReader
        self.mailReader = mailReader
        self.memoryStore = memoryStore
        self.assistantService = assistantService
        self.notificationService = notificationService
    }

    func start() {
        refreshContext()
    }

    func refreshContext() {
        Task {
            async let loadedMemories = memoryStore.loadMemories()
            async let loadedCalendar = readCalendarContext()
            async let loadedMail = readMailContext()

            memories = await loadedMemories
            calendarContext = await loadedCalendar
            mailContext = await loadedMail

            let context = currentContext()
            recommendation = await assistantService.recommendation(for: context)
            modelStatusText = "Ready"
            notifyIfNeeded(for: recommendation)
        }
    }

    func sendPrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !isResponding else {
            return
        }

        prompt = ""
        messages.append(ChatMessage(role: .user, text: trimmedPrompt))
        isResponding = true

        Task {
            let context = currentContext()
            let response = await assistantService.respond(to: trimmedPrompt, context: context)

            if let memoryCandidate = response.memoryCandidate {
                memories = await memoryStore.saveMemoryIfNeeded(memoryCandidate)
            }

            recommendation = response.recommendation
            messages.append(ChatMessage(role: .friday, text: response.message))
            modelStatusText = response.usedFoundationModel ? "Apple Intelligence" : "Local planning mode"
            isResponding = false
            notifyIfNeeded(for: response.recommendation)
        }
    }

    private func readCalendarContext() async -> CalendarContext {
        do {
            return try await calendarReader.context(now: Date())
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    private func readMailContext() async -> MailContext {
        do {
            return try await mailReader.context()
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    private func currentContext() -> AssistantContext {
        AssistantContext(
            now: Date(),
            calendar: calendarContext,
            mail: mailContext,
            memories: memories
        )
    }

    private func notifyIfNeeded(for recommendation: AssistantRecommendation) {
        guard recommendation.priority == .high else {
            return
        }

        guard recommendation.title != lastNotifiedRecommendationTitle else {
            return
        }

        if let lastNotificationDate, Date().timeIntervalSince(lastNotificationDate) < 3600 {
            return
        }

        notificationService.sendLocalNotification(
            title: recommendation.title,
            body: recommendation.nextStep
        )

        lastNotificationDate = Date()
        lastNotifiedRecommendationTitle = recommendation.title
    }
}

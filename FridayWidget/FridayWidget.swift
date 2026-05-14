//
//  FridayWidget.swift
//  FridayWidget
//
//  Created by Ved Panse on 5/13/26.
//

import EventKit
import SwiftUI
import WidgetKit

#if canImport(FoundationModels)
import FoundationModels
#endif

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FridayWidgetEntry {
        FridayWidgetEntry.placeholder
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> FridayWidgetEntry {
        if context.isPreview {
            return .placeholder
        }

        return await entry(configuration: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<FridayWidgetEntry> {
        let currentEntry = await entry(configuration: configuration)
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentEntry.date) ?? Date()
        return Timeline(entries: [currentEntry], policy: .after(refreshDate))
    }

    private func entry(configuration: ConfigurationAppIntent) async -> FridayWidgetEntry {
        let now = Date()
        let context = await FridayWidgetCalendarReader().context(now: now)
        let fallback = FridayWidgetRecommendationEngine.recommendation(for: context)
        let recommendation = await FridayWidgetAIAdvisor().recommendation(
            fallback: fallback,
            context: context,
            configuration: configuration
        )

        return FridayWidgetEntry(
            date: now,
            configuration: configuration,
            recommendation: recommendation,
            calendarStatus: context.statusMessage,
            upcomingEvents: Array(context.events.prefix(3))
        )
    }
}

struct FridayWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let recommendation: FridayWidgetRecommendation
    let calendarStatus: String?
    let upcomingEvents: [FridayWidgetCalendarEvent]

    static let placeholder = FridayWidgetEntry(
        date: Date(),
        configuration: ConfigurationAppIntent(),
        recommendation: FridayWidgetRecommendation(
            title: "Review MATH 189",
            reason: "Your exam is this week, so this is the highest-leverage block.",
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .minute, value: 45, to: Date()) ?? Date(),
            priority: .high
        ),
        calendarStatus: nil,
        upcomingEvents: [
            FridayWidgetCalendarEvent(
                title: "MATH 189 Exam",
                startDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
                endDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
                isAllDay: false
            ),
        ]
    )
}

struct FridayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var entry: Provider.Entry

    var body: some View {
        ZStack {
            FridayWidgetBackground()

            switch family {
            case .systemSmall:
                compactLayout
            case .systemLarge, .systemExtraLarge:
                expandedLayout
            default:
                mediumLayout
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(compact: true)

            Spacer(minLength: 0)

            Text(entry.recommendation.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.78)

            timePill
        }
        .padding(15)
    }

    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                header(compact: false)

                Spacer(minLength: 0)

                Text(entry.recommendation.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(entry.recommendation.reason)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                priorityBadge
                Spacer(minLength: 0)
                timeBlock
            }
        }
        .padding(16)
    }

    private var expandedLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                header(compact: false)
                Spacer()
                priorityBadge
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.recommendation.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(entry.recommendation.reason)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(3)
            }

            timeBlock

            if !entry.upcomingEvents.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Next up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))

                    ForEach(entry.upcomingEvents) { event in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.white.opacity(0.4))
                                .frame(width: 5, height: 5)

                            Text(event.title)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.76))
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Text(event.startDate, style: .time)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.52))
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 9) {
            FridayWidgetMark()
                .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Friday")
                    .font((compact ? Font.callout : .headline).weight(.semibold))
                    .foregroundStyle(.white)

                if !compact {
                    Text(entry.calendarStatus ?? "Next best step")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(1)
                }
            }
        }
    }

    private var timePill: some View {
        Text(entry.recommendation.timeRangeText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(.black.opacity(0.24), in: .rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
    }

    private var timeBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Focus block")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.54))

            Text(entry.recommendation.timeRangeText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.24), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var priorityBadge: some View {
        Text(entry.recommendation.priority.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(entry.recommendation.priority.color.opacity(0.28), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }
}

struct FridayWidget: Widget {
    let kind: String = "FridayWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            FridayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Friday")
        .description("Shows the next best focus step and the time block Friday recommends.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct FridayWidgetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.045, blue: 0.055),
                    Color(red: 0.11, green: 0.10, blue: 0.12),
                    Color(red: 0.015, green: 0.017, blue: 0.02),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.04),
                    Color.clear,
                ],
                center: .topLeading,
                startRadius: 12,
                endRadius: 220
            )

            VStack {
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.36, green: 0.22, blue: 0.85).opacity(0.82),
                                Color(red: 0.72, green: 0.08, blue: 0.56).opacity(0.78),
                                Color(red: 0.95, green: 0.15, blue: 0.22).opacity(0.78),
                                Color(red: 0.95, green: 0.36, blue: 0.02).opacity(0.78),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 4)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                    .opacity(0.82)
            }
        }
    }
}

private struct FridayWidgetMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.78, green: 0.68, blue: 0.55).opacity(0.88))

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.58))
                .padding(3)

            Text("F")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(Color(red: 0.82, green: 0.72, blue: 0.58))
                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
        }
    }
}

private struct FridayWidgetCalendarReader {
    func context(now: Date) async -> FridayWidgetContext {
        do {
            return try await Task.detached(priority: .userInitiated) {
                try readContext(now: now)
            }.value
        } catch {
            return FridayWidgetContext(now: now, events: [], statusMessage: "Calendar unavailable")
        }
    }

    private func readContext(now: Date) throws -> FridayWidgetContext {
        let eventStore = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else {
            return FridayWidgetContext(now: now, events: [], statusMessage: "Open Friday for calendar access")
        }

        let calendar = Calendar.current
        guard let endDate = calendar.date(byAdding: .day, value: 7, to: now) else {
            return FridayWidgetContext(now: now, events: [], statusMessage: "Calendar unavailable")
        }

        let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map {
                FridayWidgetCalendarEvent(
                    title: $0.title ?? "Untitled",
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isAllDay: $0.isAllDay
                )
            }

        return FridayWidgetContext(now: now, events: events, statusMessage: nil)
    }
}

private struct FridayWidgetAIAdvisor {
    func recommendation(
        fallback: FridayWidgetRecommendation,
        context: FridayWidgetContext,
        configuration: ConfigurationAppIntent
    ) async -> FridayWidgetRecommendation {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            do {
                let session = LanguageModelSession(instructions: """
                You are Friday, a concise personal AI assistant. Recommend exactly one next focus step.
                Use calendar titles and timing only. Do not claim to read email or private documents.
                Return one line in this format: Title | Reason
                Keep title under 42 characters and reason under 95 characters.
                """)
                let response = try await session.respond(to: prompt(fallback: fallback, context: context, configuration: configuration))
                return fallback.replacingText(with: response.content)
            } catch {
                return fallback
            }
        }
        #endif

        return fallback
    }

    private func prompt(
        fallback: FridayWidgetRecommendation,
        context: FridayWidgetContext,
        configuration: ConfigurationAppIntent
    ) -> String {
        """
        Current time: \(context.now.formatted(date: .abbreviated, time: .shortened))
        Recommended time block: \(fallback.timeRangeText)
        User focus preference: \(configuration.focusStyle.rawValue)

        Upcoming calendar:
        \(context.events.prefix(10).map { "- \($0.title), \($0.startDate.formatted(date: .abbreviated, time: .shortened)) to \($0.endDate.formatted(date: .omitted, time: .shortened))" }.joined(separator: "\n"))

        Fallback recommendation:
        \(fallback.title) | \(fallback.reason)
        """
    }
}

private enum FridayWidgetRecommendationEngine {
    static func recommendation(for context: FridayWidgetContext) -> FridayWidgetRecommendation {
        let calendar = Calendar.current
        let now = context.now
        let focusStart = roundedFocusStart(from: now)
        let nextTimedEvent = context.events.first { !$0.isAllDay && $0.startDate > now }

        if let urgentEvent = urgentEvent(in: context.events, now: now) {
            let duration = focusDuration(before: nextTimedEvent, start: focusStart, preferredMinutes: 50)
            return FridayWidgetRecommendation(
                title: "Prepare for \(urgentEvent.shortTitle)",
                reason: "\(urgentEvent.shortTitle) is coming up soon, so preparation has the highest payoff.",
                startDate: focusStart,
                endDate: calendar.date(byAdding: .minute, value: duration, to: focusStart) ?? focusStart,
                priority: .high
            )
        }

        if let nextTimedEvent, nextTimedEvent.startDate.timeIntervalSince(now) <= 90 * 60 {
            let duration = focusDuration(before: nextTimedEvent, start: focusStart, preferredMinutes: 25)
            return FridayWidgetRecommendation(
                title: "Prep for \(nextTimedEvent.shortTitle)",
                reason: "This is your next calendar commitment, so a short prep block reduces friction.",
                startDate: focusStart,
                endDate: calendar.date(byAdding: .minute, value: duration, to: focusStart) ?? focusStart,
                priority: .normal
            )
        }

        let duration = focusDuration(before: nextTimedEvent, start: focusStart, preferredMinutes: 45)
        return FridayWidgetRecommendation(
            title: "Choose one meaningful task",
            reason: "No urgent deadline is visible, so use this window for focused progress.",
            startDate: focusStart,
            endDate: calendar.date(byAdding: .minute, value: duration, to: focusStart) ?? focusStart,
            priority: .normal
        )
    }

    private static func urgentEvent(in events: [FridayWidgetCalendarEvent], now: Date) -> FridayWidgetCalendarEvent? {
        events.first { event in
            let daysUntilEvent = Calendar.current.dateComponents([.day], from: now, to: event.startDate).day ?? 99
            return daysUntilEvent <= 7 && event.title.lowercased().containsAny(of: [
                "exam",
                "midterm",
                "final",
                "quiz",
                "deadline",
                "due",
                "interview",
            ])
        }
    }

    private static func roundedFocusStart(from date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let remainder = minute % 5
        guard remainder != 0 else { return date }
        return calendar.date(byAdding: .minute, value: 5 - remainder, to: date) ?? date
    }

    private static func focusDuration(
        before nextEvent: FridayWidgetCalendarEvent?,
        start: Date,
        preferredMinutes: Int
    ) -> Int {
        guard let nextEvent else {
            return preferredMinutes
        }

        let availableMinutes = Int(nextEvent.startDate.timeIntervalSince(start) / 60) - 10
        return max(15, min(preferredMinutes, availableMinutes))
    }
}

private struct FridayWidgetContext: Equatable {
    let now: Date
    let events: [FridayWidgetCalendarEvent]
    let statusMessage: String?
}

struct FridayWidgetCalendarEvent: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool

    var shortTitle: String {
        title
            .replacingOccurrences(of: "Exam", with: "")
            .replacingOccurrences(of: "exam", with: "")
            .replacingOccurrences(of: "Deadline", with: "")
            .replacingOccurrences(of: "deadline", with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .prefixString(24)
    }
}

struct FridayWidgetRecommendation: Equatable {
    let title: String
    let reason: String
    let startDate: Date
    let endDate: Date
    let priority: FridayWidgetPriority

    var timeRangeText: String {
        "\(startDate.formatted(date: .omitted, time: .shortened)) - \(endDate.formatted(date: .omitted, time: .shortened))"
    }

    func replacingText(with aiText: String) -> FridayWidgetRecommendation {
        let parts = aiText
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }

        guard let title = parts.first, !title.isEmpty else {
            return self
        }

        return FridayWidgetRecommendation(
            title: title.prefixString(58),
            reason: (parts.dropFirst().first ?? reason).prefixString(140),
            startDate: startDate,
            endDate: endDate,
            priority: priority
        )
    }
}

enum FridayWidgetPriority: Equatable {
    case normal
    case high

    var title: String {
        switch self {
        case .normal:
            "NOW"
        case .high:
            "HIGH"
        }
    }

    var color: Color {
        switch self {
        case .normal:
            Color.white
        case .high:
            Color(red: 0.95, green: 0.22, blue: 0.26)
        }
    }
}

private extension String {
    func containsAny(of needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }

    func prefixString(_ count: Int) -> String {
        String(prefix(count))
    }
}

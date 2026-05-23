//
//  AssistantContextReaders.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import AppKit
import EventKit
import Foundation

protocol CalendarContextReading: Sendable {
    func context(now: Date) async throws -> CalendarContext
}

protocol MailContextReading: Sendable {
    func context() async throws -> MailContext
}

final class EventKitCalendarContextReader: CalendarContextReading, @unchecked Sendable {
    nonisolated init() {}

    nonisolated func context(now: Date = Date()) async throws -> CalendarContext {
        try await Task.detached(priority: .userInitiated) {
            let eventStore = EKEventStore()
            try await Self.requestCalendarAccessIfNeeded(using: eventStore)
            eventStore.refreshSourcesIfNecessary()

            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: now)
            guard
                let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
                let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday)
            else {
                throw AssistantContextError.invalidDateRange
            }

            let allCalendars = eventStore.fridayAllEventCalendars()
            let queryCalendars = allCalendars.isEmpty ? nil : allCalendars
            let todayPredicate = eventStore.predicateForEvents(withStart: now, end: startOfTomorrow, calendars: queryCalendars)
            let weekPredicate = eventStore.predicateForEvents(withStart: now, end: endOfWeek, calendars: queryCalendars)

            let eventsToday = eventStore.events(matching: todayPredicate)
                .map { CalendarEvent(event: $0) }
                .sorted { $0.startDate < $1.startDate }

            let upcomingEvents = eventStore.events(matching: weekPredicate)
                .map { CalendarEvent(event: $0) }
                .sorted { $0.startDate < $1.startDate }

            return CalendarContext(
                eventsToday: eventsToday,
                upcomingEvents: upcomingEvents,
                statusMessage: nil
            )
        }.value
    }

    private nonisolated static func requestCalendarAccessIfNeeded(using eventStore: EKEventStore) async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            let isGranted = try await requestFullCalendarAccess(using: eventStore)
            guard isGranted else { throw AssistantContextError.calendarAccessDenied }
        case .denied, .restricted, .writeOnly:
            throw AssistantContextError.calendarAccessDenied
        @unknown default:
            throw AssistantContextError.calendarAccessDenied
        }
    }

    private nonisolated static func requestFullCalendarAccess(using eventStore: EKEventStore) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { isGranted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: isGranted)
                }
            }
        }
    }
}

nonisolated private extension EKEventStore {
    func fridayAllEventCalendars() -> [EKCalendar] {
        let directCalendars = calendars(for: .event)
        let sourceCalendars = sources.flatMap { source in
            Array(source.calendars(for: .event))
        }

        var seenCalendarIDs = Set<String>()
        return (directCalendars + sourceCalendars).filter { calendar in
            seenCalendarIDs.insert(calendar.calendarIdentifier).inserted
        }
    }
}

final class MailAppleScriptContextReader: MailContextReading, @unchecked Sendable {
    private nonisolated static let mailBundleIdentifier = "com.apple.mail"

    nonisolated init() {}

    nonisolated func context() async throws -> MailContext {
        let result = try await Task.detached(priority: .userInitiated) {
            try Self.executeInboxScript()
        }.value

        return MailContext(
            unreadCount: result.unreadCount,
            latestSubject: result.recentSubjects.first,
            recentSubjects: result.recentSubjects,
            statusMessage: nil
        )
    }

    private nonisolated static func executeInboxScript() throws -> (unreadCount: Int, recentSubjects: [String]) {
        guard isMailRunning else {
            throw AssistantContextError.mailNotRunning
        }

        let source = """
        tell application id "\(mailBundleIdentifier)"
            set unreadMessages to messages of inbox whose read status is false
            set unreadCount to count of unreadMessages
            set recentSubjects to {}
            set messageLimit to unreadCount

            if messageLimit is greater than 5 then
                set messageLimit to 5
            end if

            repeat with messageIndex from 1 to messageLimit
                set end of recentSubjects to subject of item messageIndex of unreadMessages
            end repeat

            return (unreadCount as text) & linefeed & (recentSubjects as text)
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            throw AssistantContextError.mailScriptUnavailable
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            throw AssistantContextError.mailAutomationFailed(message(from: errorInfo))
        }

        let output = descriptor.stringValue ?? ""
        let lines = output.components(separatedBy: .newlines)
        let unreadCount = Int(lines.first ?? "") ?? 0
        let subjects = lines
            .dropFirst()
            .flatMap { $0.components(separatedBy: ", ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (unreadCount, subjects)
    }

    private nonisolated static func message(from errorInfo: NSDictionary) -> String {
        if let message = errorInfo[NSAppleScript.errorMessage] as? String {
            if message == "Application isn’t running." || message == "Application isn't running." {
                return "Mail is open, but macOS has not made it available to Friday yet"
            }

            return message
        }

        return "Mail automation was not allowed"
    }

    private nonisolated static var isMailRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == mailBundleIdentifier
        }
    }
}

enum AssistantContextError: LocalizedError {
    case calendarAccessDenied
    case invalidDateRange
    case mailAutomationFailed(String)
    case mailNotRunning
    case mailScriptUnavailable

    var errorDescription: String? {
        switch self {
        case .calendarAccessDenied:
            "Calendar access is required"
        case .invalidDateRange:
            "Unable to build calendar range"
        case .mailAutomationFailed(let message):
            message
        case .mailNotRunning:
            "Open Mail to show inbox"
        case .mailScriptUnavailable:
            "Unable to prepare Mail automation"
        }
    }
}

private nonisolated extension CalendarEvent {
    init(event: EKEvent) {
        self.init(
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay
        )
    }
}

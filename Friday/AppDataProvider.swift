//
//  AppDataProvider.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import AppKit
import Combine
import EventKit
import Foundation

@MainActor
final class AppDataProvider: ObservableObject {
    @Published private(set) var calendarSummary = CalendarSummary.loading
    @Published private(set) var mailSummary = MailSummary.loading

    private let calendarService: CalendarReading = EventKitCalendarReader()
    private let mailService: MailReading = MailAppleScriptReader()

    func refresh() {
        calendarSummary = .loading
        mailSummary = .loading

        Task { [weak self] in
            await self?.refreshCalendar()
        }

        Task { [weak self] in
            await self?.refreshMail()
        }
    }

    func refreshCalendar() async {
        do {
            calendarSummary = try await calendarService.todaySummary()
        } catch {
            calendarSummary = .unavailable(error.localizedDescription)
        }
    }

    func refreshMail() async {
        do {
            mailSummary = try await mailService.inboxSummary()
        } catch {
            mailSummary = .unavailable(error.localizedDescription)
        }
    }
}

struct CalendarSummary: Equatable {
    let eventCount: Int
    let nextEventTitle: String?
    let statusMessage: String?

    static let loading = CalendarSummary(
        eventCount: 0,
        nextEventTitle: nil,
        statusMessage: "Checking calendar access"
    )

    static func unavailable(_ message: String) -> CalendarSummary {
        CalendarSummary(eventCount: 0, nextEventTitle: nil, statusMessage: message)
    }
}

struct MailSummary: Equatable {
    let unreadCount: Int
    let latestSubject: String?
    let statusMessage: String?

    static let loading = MailSummary(
        unreadCount: 0,
        latestSubject: nil,
        statusMessage: "Checking Mail access"
    )

    static func unavailable(_ message: String) -> MailSummary {
        MailSummary(unreadCount: 0, latestSubject: nil, statusMessage: message)
    }
}

protocol CalendarReading {
    func todaySummary() async throws -> CalendarSummary
}

protocol MailReading {
    func inboxSummary() async throws -> MailSummary
}

private final class EventKitCalendarReader: CalendarReading {
    private let eventStore = EKEventStore()

    func todaySummary() async throws -> CalendarSummary {
        try await requestCalendarAccessIfNeeded()
        eventStore.refreshSourcesIfNecessary()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw AppDataError.invalidDateRange
        }

        let allCalendars = eventStore.fridayAllEventCalendars()
        let predicate = eventStore.predicateForEvents(
            withStart: Date(),
            end: endOfDay,
            calendars: allCalendars.isEmpty ? nil : allCalendars
        )

        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        return CalendarSummary(
            eventCount: events.count,
            nextEventTitle: events.first?.title,
            statusMessage: nil
        )
    }

    private func requestCalendarAccessIfNeeded() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            let isGranted = try await requestFullCalendarAccess()
            guard isGranted else { throw AppDataError.calendarAccessDenied }
        case .denied, .restricted, .writeOnly:
            throw AppDataError.calendarAccessDenied
        @unknown default:
            throw AppDataError.calendarAccessDenied
        }
    }

    private func requestFullCalendarAccess() async throws -> Bool {
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

private final class MailAppleScriptReader: MailReading {
    private nonisolated static let mailBundleIdentifier = "com.apple.mail"

    func inboxSummary() async throws -> MailSummary {
        let result = try await Task.detached(priority: .userInitiated) {
            try Self.executeInboxScript()
        }.value

        return MailSummary(
            unreadCount: result.unreadCount,
            latestSubject: result.latestSubject,
            statusMessage: nil
        )
    }

    private nonisolated static func executeInboxScript() throws -> (unreadCount: Int, latestSubject: String?) {
        guard isMailRunning else {
            throw AppDataError.mailNotRunning
        }

        let source = """
        tell application id "\(mailBundleIdentifier)"
            set unreadMessages to messages of inbox whose read status is false
            set unreadCount to count of unreadMessages
            set latestSubject to ""

            if unreadCount is greater than 0 then
                set latestSubject to subject of item 1 of unreadMessages
            end if

            return (unreadCount as text) & linefeed & latestSubject
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            throw AppDataError.mailScriptUnavailable
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            throw AppDataError.mailAutomationFailed(message(from: errorInfo))
        }

        let output = descriptor.stringValue ?? ""
        let parts = output.components(separatedBy: .newlines)
        let unreadCount = Int(parts.first ?? "") ?? 0
        let latestSubject = parts.dropFirst().first.flatMap { $0.isEmpty ? nil : $0 }

        return (unreadCount, latestSubject)
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

private enum AppDataError: LocalizedError {
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
            "Unable to build today's calendar range"
        case .mailAutomationFailed(let message):
            message
        case .mailNotRunning:
            "Open Mail to show inbox"
        case .mailScriptUnavailable:
            "Unable to prepare Mail automation"
        }
    }
}

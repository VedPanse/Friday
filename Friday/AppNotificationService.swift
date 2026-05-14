//
//  AppNotificationService.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import AppKit
import Foundation
import UserNotifications

nonisolated final class AppNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()
    private let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")

    private(set) var remoteDeviceToken: String?

    private override init() {
        super.init()
    }

    func configure() {
        notificationCenter.delegate = self

        Task {
            await requestAuthorizationIfNeeded()
        }
    }

    func sendLocalNotification(title: String, body: String) {
        Task {
            guard await canSendNotifications() else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            do {
                try await notificationCenter.add(request)
            } catch {
                NSLog("Friday could not schedule notification: \(error.localizedDescription)")
            }
        }
    }

    func didRegisterForRemoteNotifications(with deviceToken: Data) {
        remoteDeviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    func didFailToRegisterForRemoteNotifications(with error: Error) {
        remoteDeviceToken = nil
        NSLog("Friday failed to register for remote notifications: \(error.localizedDescription)")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private func requestAuthorizationIfNeeded() async {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            NSLog("Friday notifications are disabled in macOS Settings.")
            return
        case .notDetermined:
            await requestAuthorization()
        @unknown default:
            return
        }
    }

    private func requestAuthorization() async {
        do {
            let isAuthorized = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            if !isAuthorized {
                NSLog("Friday notifications were not authorized.")
            }
        } catch {
            NSLog("Friday could not request notification authorization. Enable notifications for Friday in macOS Settings. \(error.localizedDescription)")
        }
    }

    private func canSendNotifications() async -> Bool {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            NSLog("Friday skipped notification because notifications are disabled in macOS Settings.")
            return false
        case .notDetermined:
            await requestAuthorization()
            return await canSendNotifications()
        @unknown default:
            return false
        }
    }

    func openNotificationSettings() {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }
}

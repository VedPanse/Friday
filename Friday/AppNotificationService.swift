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

    private(set) var remoteDeviceToken: String?

    private override init() {
        super.init()
    }

    func configure() {
        notificationCenter.delegate = self

        Task {
            await requestAuthorization()
        }
    }

    func sendLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
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

    private func requestAuthorization() async {
        do {
            _ = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            NSLog("Friday failed to request notification authorization: \(error.localizedDescription)")
        }
    }
}

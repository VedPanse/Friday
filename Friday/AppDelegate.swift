//
//  AppDelegate.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppNotificationService.shared.configure()
        FridayWindowController.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        AppNotificationService.shared.didRegisterForRemoteNotifications(with: deviceToken)
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        AppNotificationService.shared.didFailToRegisterForRemoteNotifications(with: error)
    }
}

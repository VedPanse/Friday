//
//  FridayApp.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import SwiftUI

@main
struct FridayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .windowArrangement) {
                Button("Hide Friday") {
                    FridayWindowController.shared.hideWindow()
                }
                .keyboardShortcut("m", modifiers: .command)
            }
        }
    }
}

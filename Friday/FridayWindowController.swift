//
//  FridayWindowController.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import AppKit
import Carbon
import Foundation

extension Notification.Name {
    static let fridayFocusPrompt = Notification.Name("FridayFocusPrompt")
}

final class FridayWindowController {
    static let shared = FridayWindowController()

    private var statusItem: NSStatusItem?
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    private init() {}

    func start() {
        installStatusItem()
        registerShowShortcut()
    }

    func hideWindow() {
        NSApp.windows
            .filter { $0.isVisible }
            .forEach { $0.orderOut(nil) }

        NSApp.setActivationPolicy(.accessory)
    }

    func showWindowAndFocusPrompt() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { !$0.isMiniaturized }) ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.centerIfNeeded()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .fridayFocusPrompt, object: nil)
        }
    }

    private func installStatusItem() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Friday")
        item.button?.imagePosition = .imageLeading
        item.button?.title = "Friday"

        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Friday", action: #selector(StatusItemTarget.showFriday), keyEquivalent: "")
        showItem.target = StatusItemTarget.shared
        menu.addItem(showItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Friday", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func registerShowShortcut() {
        guard hotKeyReference == nil else {
            return
        }

        let hotKeyID = EventHotKeyID(signature: FourCharCode("FRDY"), id: 1)
        let modifierFlags = UInt32(cmdKey | optionKey)
        let keyCode = UInt32(kVK_ANSI_F)

        RegisterEventHotKey(
            keyCode,
            modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if hotKeyID.signature == FourCharCode("FRDY"), hotKeyID.id == 1 {
                    FridayWindowController.shared.showWindowAndFocusPrompt()
                }

                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerReference
        )
    }
}

private final class StatusItemTarget: NSObject {
    static let shared = StatusItemTarget()

    @objc func showFriday() {
        FridayWindowController.shared.showWindowAndFocusPrompt()
    }
}

private extension NSWindow {
    func centerIfNeeded() {
        guard !isVisible else {
            return
        }

        center()
    }
}

private func FourCharCode(_ string: String) -> FourCharCode {
    string.utf8.reduce(0) { result, character in
        (result << 8) + FourCharCode(character)
    }
}

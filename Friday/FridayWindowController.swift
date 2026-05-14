//
//  FridayWindowController.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import AppKit
import Carbon
import Combine
import Foundation
import ScreenCaptureKit
import Security
import SwiftUI

extension Notification.Name {
    static let fridayFocusPrompt = Notification.Name("FridayFocusPrompt")
    static let fridayScreenIntelligenceFocusPrompt = Notification.Name("FridayScreenIntelligenceFocusPrompt")
}

final class FridayWindowController {
    static let shared = FridayWindowController()

    private var statusItem: NSStatusItem?
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var screenIntelligencePanel: NSPanel?

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

    func showScreenIntelligenceIsland() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let screenIntelligencePanel {
            screenIntelligencePanel.centerOnActiveScreen()
            screenIntelligencePanel.orderFrontRegardless()
            screenIntelligencePanel.makeKey()
            refocusScreenIntelligencePrompt()
            return
        }

        let panel = ScreenIntelligencePanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 78),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: ScreenIntelligenceIsland())
        panel.centerOnActiveScreen()
        panel.orderFrontRegardless()
        panel.makeKey()

        screenIntelligencePanel = panel
        refocusScreenIntelligencePrompt()
    }

    func hideScreenIntelligenceIsland() {
        screenIntelligencePanel?.orderOut(nil)
        screenIntelligencePanel = nil
    }

    private func refocusScreenIntelligencePrompt() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .fridayScreenIntelligenceFocusPrompt, object: nil)
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
        let screenItem = NSMenuItem(title: "Ask About Screen", action: #selector(StatusItemTarget.askAboutScreen), keyEquivalent: "")
        screenItem.target = StatusItemTarget.shared
        menu.addItem(screenItem)

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
                    FridayWindowController.shared.showScreenIntelligenceIsland()
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

    @objc func askAboutScreen() {
        FridayWindowController.shared.showScreenIntelligenceIsland()
    }
}

private final class ScreenIntelligencePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        FridayWindowController.shared.hideScreenIntelligenceIsland()
    }
}

private extension NSWindow {
    func centerIfNeeded() {
        guard !isVisible else {
            return
        }

        center()
    }

    func centerOnActiveScreen() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else {
            center()
            return
        }

        setFrameOrigin(NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.maxY - frame.height - 96
        ))
    }
}

private struct ScreenIntelligenceIsland: View {
    @StateObject private var viewModel = ScreenIntelligenceViewModel()
    @FocusState private var isPromptFocused: Bool
    @State private var isHovered = false
    @State private var isStopHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: viewModel.answer.isEmpty ? 0 : 12) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                TextField("Ask Friday about what is on your screen", text: $viewModel.prompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($isPromptFocused)
                    .onSubmit(viewModel.ask)

                if viewModel.isThinking {
                    Button(action: viewModel.cancel) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(isStopHovered ? 0.38 : 0.24), in: Circle())
                    .onHover { isStopHovered = $0 }
                } else {
                    KeyboardShortcutPillView(text: "⌘⌥F")
                }
            }
            .frame(height: 52)

            if viewModel.isThinking {
                ScreenThinkingBar()
            }

            if !viewModel.answer.isEmpty {
                FridayMarkdownView(markdown: viewModel.answer)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(width: 720)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
        .background(Color.black.opacity(isHovered ? 0.34 : 0.27), in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(isHovered ? 0.28 : 0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 28, x: 0, y: 18)
        .onHover { isHovered = $0 }
        .onAppear {
            focusPromptSoon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fridayScreenIntelligenceFocusPrompt)) { _ in
            focusPromptSoon()
        }
        .onExitCommand {
            FridayWindowController.shared.hideScreenIntelligenceIsland()
        }
    }

    private func focusPromptSoon() {
        DispatchQueue.main.async {
            isPromptFocused = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            isPromptFocused = true
        }
    }
}

@MainActor
private final class ScreenIntelligenceViewModel: ObservableObject {
    @Published var prompt = ""
    @Published private(set) var answer = ""
    @Published private(set) var isThinking = false

    private var task: Task<Void, Never>?

    func ask() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !isThinking else { return }

        prompt = ""
        answer = ""
        isThinking = true

        task?.cancel()
        task = Task {
            let response = await ScreenIntelligenceService().answer(question: trimmedPrompt)
            guard !Task.isCancelled else { return }
            answer = response
            isThinking = false
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isThinking = false
        answer = "Stopped."
    }
}

private struct ScreenIntelligenceService {
    func answer(question: String) async -> String {
        guard let apiKey = ScreenIntelligenceKeychain.openAIAPIKey, !apiKey.isEmpty else {
            return "Add your OpenAI API key in Friday Settings so I can understand what is on your screen."
        }

        guard let imageDataURL = await ScreenCapture.snapshotDataURL() else {
            return "I could not capture the screen. Enable Screen Recording permission for Friday in macOS Privacy & Security, then try again."
        }

        do {
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": "gpt-5.4-mini",
                "max_output_tokens": 500,
                "instructions": """
                You are Friday, a friendly screen-aware assistant. The user and you are looking at the same laptop screen.
                Answer concretely based on the screenshot. If something is not visible, say so.
                Be concise and helpful. Do not claim to click or change anything.
                """,
                "input": [
                    [
                        "role": "user",
                        "content": [
                            ["type": "input_text", "text": question],
                            ["type": "input_image", "image_url": imageDataURL],
                        ],
                    ],
                ],
            ] as [String: Any])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return "I could not get a screen-aware answer right now."
            }

            return Self.extractText(from: data).isEmpty ? "I could not read a useful answer from the model." : Self.extractText(from: data)
        } catch {
            return "Screen intelligence failed: \(error.localizedDescription)"
        }
    }

    private static func extractText(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }

        if let outputText = object["output_text"] as? String {
            return outputText
        }

        guard let output = object["output"] as? [[String: Any]] else {
            return ""
        }

        return output
            .compactMap { item -> String? in
                guard let content = item["content"] as? [[String: Any]] else { return nil }
                return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            }
            .joined(separator: "\n")
    }
}

private enum ScreenCapture {
    static func snapshotDataURL() async -> String? {
        guard let image = await snapshotImage() else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else {
            return nil
        }

        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private static func snapshotImage() async -> CGImage? {
        await withCheckedContinuation { continuation in
            let rect = captureRect()
            SCScreenshotManager.captureImage(in: rect) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func captureRect() -> CGRect {
        if let screen = NSScreen.main {
            return screen.frame
        }

        let union = NSScreen.screens.reduce(CGRect.null) { partialResult, screen in
            partialResult.union(screen.frame)
        }

        return union.isNull ? CGRect(x: 0, y: 0, width: 1440, height: 900) : union
    }
}

private enum ScreenIntelligenceKeychain {
    private static let service = "com.vedpanse.Friday"
    private static let openAIAccount = "openai-api-key"

    static var openAIAPIKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openAIAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        }

        return String(data: data, encoding: .utf8)
    }
}

private struct KeyboardShortcutPillView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.64))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.black.opacity(0.22), in: .rect(cornerRadius: 8, style: .continuous))
    }
}

private struct ScreenThinkingBar: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.28, green: 0.72, blue: 1).opacity(0.8),
                                    Color(red: 0.9, green: 0.28, blue: 1).opacity(0.8),
                                    Color(red: 0.3, green: 1, blue: 0.72).opacity(0.8),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * 0.34)
                        .offset(x: CGFloat((sin(time * 1.8) * 0.5 + 0.5)) * geometry.size.width * 0.66)
                        .blur(radius: 0.5)
                }
            }
        }
        .frame(height: 3)
    }
}

private func FourCharCode(_ string: String) -> FourCharCode {
    string.utf8.reduce(0) { result, character in
        (result << 8) + FourCharCode(character)
    }
}

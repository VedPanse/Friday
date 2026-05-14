//
//  ContentView.swift
//  Friday
//
//  Created by Ved Panse on 5/13/26.
//

import AppKit
import Combine
import EventKit
import PDFKit
import Security
import SwiftUI
import UniformTypeIdentifiers
import WebKit

#if canImport(FoundationModels)
import FoundationModels
#endif

private let fridayFocusPromptNotification = Notification.Name("FridayFocusPrompt")

struct ContentView: View {
    @StateObject private var assistantStore = FridayAssistantStore()
    @State private var selection = SidebarItem.home

    var body: some View {
        HStack(alignment: .center, spacing: Layout.sidebarSpacing) {
            SidebarView(selection: $selection)

            ZStack {
                switch selection {
                case .home:
                    MainGlassPanel(assistantStore: assistantStore)
                        .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.98)))
                case .search:
                    SearchOverlay(isPresented: isSearchPresented)
                        .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.98)))
                case .mail:
                    StubPanel(
                        systemName: "mail.stack",
                        title: "Mail",
                        subtitle: "Inbox, VIPs, flagged messages, and quick replies will live here."
                    )
                    .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.98)))
                case .calendar:
                    StubPanel(
                        systemName: "calendar",
                        title: "Calendar",
                        subtitle: "Upcoming events, schedule gaps, and meeting prep will live here."
                    )
                    .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.98)))
                case .stocks:
                    StockMarketPanel()
                        .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.98)))
                case .saved:
                    StubPanel(
                        systemName: "bookmark",
                        title: "Saved",
                        subtitle: "Pinned notes, saved searches, and important references will live here."
                    )
                    .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.98)))
                case .settings:
                    SettingsPanel(store: assistantStore)
                    .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.98)))
                default:
                    MainGlassPanel(assistantStore: assistantStore)
                        .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .frame(width: Layout.contentAreaWidth, height: Layout.contentAreaHeight)
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: selection)
        .padding(Layout.windowPadding)
        .frame(minWidth: Layout.minimumWindowWidth, minHeight: Layout.minimumWindowHeight)
        .background(WindowTransparencyConfigurator())
        .onReceive(NotificationCenter.default.publisher(for: fridayFocusPromptNotification)) { _ in
            selection = .home
        }
    }

    private var isSearchPresented: Binding<Bool> {
        Binding(
            get: { selection == .search },
            set: { isPresented in
                if !isPresented {
                    selection = .home
                }
            }
        )
    }
}

private struct MainGlassPanel: View {
    @ObservedObject var assistantStore: FridayAssistantStore
    @StateObject private var dataProvider = HomePanelDataProvider()
    @StateObject private var viewModel: FridayPanelChatViewModel
    @FocusState private var isPromptFocused: Bool
    @Namespace private var panelAnimation
    @State private var isCreateHovered = false
    @State private var isConversationPresented = false

    init(assistantStore: FridayAssistantStore) {
        self.assistantStore = assistantStore
        _viewModel = StateObject(wrappedValue: FridayPanelChatViewModel(store: assistantStore))
    }

    var body: some View {
        Group {
            if let browserSession = viewModel.browserSession {
                BrowserWorkspace(
                    viewModel: viewModel,
                    session: browserSession,
                    namespace: panelAnimation,
                    closeBrowser: closeBrowser
                )
                .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                ZStack {
                    if isConversationPresented {
                        FridayConversationPanel(
                            viewModel: viewModel,
                            isPresented: $isConversationPresented,
                            namespace: panelAnimation
                        )
                        .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.985)))
                    } else {
                        homeContent
                            .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.985)))
                    }
                }
                .padding(Layout.panelPadding)
                .frame(width: Layout.panelWidth, height: Layout.panelHeight)
                .glassSurface(cornerRadius: Layout.panelCornerRadius)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isConversationPresented)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: viewModel.browserSession?.id)
        .task {
            dataProvider.refresh()
            viewModel.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: fridayFocusPromptNotification)) { _ in
            isPromptFocused = true
        }
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: Layout.panelSpacing) {
            header

            PromptField(
                text: $viewModel.prompt,
                placeholder: "What can I help with?",
                isFocused: $isPromptFocused,
                namespace: panelAnimation,
                matchedGeometryID: "fridayPrompt",
                onSubmit: beginConversation
            )

            VStack(spacing: Layout.rowSpacing) {
                ForEach(contextItems) { item in
                    ContentRow(item: item)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: Layout.headerSpacing) {
            Circle()
                .fill(AppColor.black.opacity(0.2))
                .frame(width: Layout.appIconSize, height: Layout.appIconSize)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.white)
                }

            Text("Friday")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Button(action: addItem) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.white)
            }
            .buttonStyle(.plain)
            .frame(width: Layout.headerButtonSize, height: Layout.headerButtonSize)
            .background(AppColor.black.opacity(isCreateHovered ? 0.28 : 0.2), in: Circle())
            .scaleEffect(isCreateHovered ? 1.06 : 1)
            .cursor(.pointingHand)
            .onHover { isCreateHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isCreateHovered)
            .help("Create")
            .accessibilityLabel("Create")
        }
    }

    private func addItem() {
        dataProvider.refresh()
    }

    private func beginConversation() {
        let trimmedPrompt = viewModel.prompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isConversationPresented = true
        }

        viewModel.sendPrompt()
    }

    private func closeBrowser() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            viewModel.closeBrowser()
            isConversationPresented = true
        }
    }

    private var contextItems: [PanelItem] {
        [
            calendarItem,
            mailItem,
            .init(systemName: "checklist", title: "Tasks", subtitle: "5 open items"),
        ]
    }

    private var calendarItem: PanelItem {
        let summary = dataProvider.calendarSummary
        let subtitle: String

        if let statusMessage = summary.statusMessage {
            subtitle = statusMessage
        } else if let nextEventTitle = summary.nextEventTitle {
            subtitle = "Next: \(nextEventTitle)"
        } else if summary.eventCount > 0 {
            subtitle = "\(summary.eventCount) events today"
        } else {
            subtitle = "No more events today"
        }

        return .init(systemName: "calendar", title: "Today", subtitle: subtitle)
    }

    private var mailItem: PanelItem {
        let summary = dataProvider.mailSummary
        let subtitle: String

        if let statusMessage = summary.statusMessage {
            subtitle = statusMessage
        } else if let latestSubject = summary.latestSubject, summary.unreadCount > 0 {
            subtitle = "\(summary.unreadCount) unread, latest: \(latestSubject)"
        } else {
            subtitle = "No unread messages"
        }

        return .init(systemName: "envelope", title: "Inbox", subtitle: subtitle)
    }
}

private struct FridayConversationPanel: View {
    @ObservedObject var viewModel: FridayPanelChatViewModel
    @Binding var isPresented: Bool
    let namespace: Namespace.ID

    @FocusState private var isPromptFocused: Bool
    @State private var isCloseHovered = false
    @State private var isFolderHovered = false
    @State private var isFileHovered = false
    @State private var isUndoHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if !viewModel.contextItems.isEmpty {
                contextStrip
            }

            if let notice = viewModel.savedMemoryNotice {
                savedMemoryChip(notice)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Layout.chatMessageSpacing) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageRow(message: message)
                                .id(message.id)
                        }

                        if viewModel.isResponding {
                            FridayTypingRow()
                                .id("fridayTyping")
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .onChange(of: viewModel.messages) { _, messages in
                    guard let lastMessage = messages.last else { return }

                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isResponding) { _, isResponding in
                    guard isResponding else { return }

                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("fridayTyping", anchor: .bottom)
                    }
                }
            }

            PromptField(
                text: $viewModel.prompt,
                placeholder: "Ask Friday anything",
                isFocused: $isPromptFocused,
                namespace: namespace,
                matchedGeometryID: "fridayPrompt",
                onSubmit: viewModel.sendPrompt
            )
        }
        .onAppear {
            isPromptFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColor.white)
            }
            .buttonStyle(.plain)
            .frame(width: Layout.headerButtonSize, height: Layout.headerButtonSize)
            .background(AppColor.black.opacity(isCloseHovered ? 0.32 : 0.2), in: Circle())
            .scaleEffect(isCloseHovered ? 1.06 : 1)
            .cursor(.pointingHand)
            .onHover { isCloseHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isCloseHovered)
            .help("Close conversation")
            .accessibilityLabel("Close conversation")

            Text("Friday")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Button(action: viewModel.openFolderContext) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.white)
            }
            .buttonStyle(.plain)
            .frame(width: Layout.headerButtonSize, height: Layout.headerButtonSize)
            .background(AppColor.black.opacity(isFolderHovered ? 0.32 : 0.2), in: Circle())
            .cursor(.pointingHand)
            .onHover { isFolderHovered = $0 }
            .help("Use a folder as context")
            .accessibilityLabel("Use folder as context")

            Button(action: viewModel.openFileContext) {
                Image(systemName: "paperclip")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.white)
            }
            .buttonStyle(.plain)
            .frame(width: Layout.headerButtonSize, height: Layout.headerButtonSize)
            .background(AppColor.black.opacity(isFileHovered ? 0.32 : 0.2), in: Circle())
            .cursor(.pointingHand)
            .onHover { isFileHovered = $0 }
            .help("Attach PDFs, images, links, or text files")
            .accessibilityLabel("Attach context")

            Text(viewModel.modelStatusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .padding(.bottom, 8)
    }

    private var contextStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(viewModel.contextItems) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.systemName)
                            .font(.system(size: 10, weight: .semibold))

                        Text(item.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(AppColor.black.opacity(0.2), in: .rect(cornerRadius: 9, style: .continuous))
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func savedMemoryChip(_ notice: FridaySavedMemoryNotice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 11, weight: .semibold))

            Text("Saved: \(notice.text)")
                .font(.caption.weight(.medium))
                .lineLimit(1)

            Button("Undo", action: viewModel.undoLastMemorySave)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(AppColor.black.opacity(isUndoHovered ? 0.34 : 0.22), in: .rect(cornerRadius: 7, style: .continuous))
                .cursor(.pointingHand)
                .onHover { isUndoHovered = $0 }
        }
        .foregroundStyle(.white.opacity(0.84))
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 30)
        .background(AppColor.black.opacity(0.22), in: .rect(cornerRadius: 10, style: .continuous))
        .padding(.bottom, 8)
        .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
    }

    private func close() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isPresented = false
        }
    }
}

private struct BrowserWorkspace: View {
    @ObservedObject var viewModel: FridayPanelChatViewModel
    let session: FridayBrowserSession
    let namespace: Namespace.ID
    let closeBrowser: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Layout.browserIslandSpacing) {
            BrowserIsland(session: session, closeBrowser: closeBrowser)

            FridayBrowserChatIsland(
                viewModel: viewModel,
                namespace: namespace
            )
        }
        .frame(width: Layout.browserWorkspaceWidth, height: Layout.panelHeight)
    }
}

private struct BrowserIsland: View {
    let session: FridayBrowserSession
    let closeBrowser: () -> Void

    @State private var addressText = ""
    @State private var isCloseHovered = false
    @State private var isReloadHovered = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Button(action: closeBrowser) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColor.white)
                }
                .buttonStyle(.plain)
                .frame(width: Layout.headerButtonSize, height: Layout.headerButtonSize)
                .background(AppColor.black.opacity(isCloseHovered ? 0.32 : 0.2), in: Circle())
                .cursor(.pointingHand)
                .onHover { isCloseHovered = $0 }
                .help("Close browser")

                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                TextField("Enter URL", text: $addressText)
                    .textFieldStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .tint(.white)
                    .lineLimit(1)
                    .onSubmit(navigateFromAddressBar)
                    .onAppear(perform: syncAddressText)
                    .onChange(of: session.visibleURL) { _, _ in syncAddressText() }
                    .onChange(of: session.requestedURL) { _, _ in syncAddressText() }

                Spacer()

                if session.isLoading {
                    Text("Loading")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.44))
                }

                Button(action: session.reload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.white)
                }
                .buttonStyle(.plain)
                .frame(width: Layout.headerButtonSize, height: Layout.headerButtonSize)
                .background(AppColor.black.opacity(isReloadHovered ? 0.32 : 0.2), in: Circle())
                .cursor(.pointingHand)
                .onHover { isReloadHovered = $0 }
                .help("Reload")
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(AppColor.black.opacity(0.22), in: .rect(cornerRadius: 14, style: .continuous))

            FridayWebView(session: session)
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColor.white.opacity(0.12), lineWidth: 1)
                }
        }
        .padding(Layout.browserPanelPadding)
        .frame(width: Layout.browserPanelWidth, height: Layout.panelHeight)
        .glassSurface(cornerRadius: Layout.panelCornerRadius)
    }

    private func syncAddressText() {
        let url = session.visibleURL ?? session.requestedURL
        guard addressText != url.absoluteString else { return }
        addressText = url.absoluteString
    }

    private func navigateFromAddressBar() {
        guard let url = FridayBrowserURLParser.url(from: addressText) else { return }
        session.navigate(to: url, userRequest: "Manual URL entry")
    }
}

private struct FridayBrowserChatIsland: View {
    @ObservedObject var viewModel: FridayPanelChatViewModel
    let namespace: Namespace.ID

    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AppColor.black.opacity(0.2))
                    .frame(width: Layout.appIconSize, height: Layout.appIconSize)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColor.white)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Friday")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Browser control")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.56))
                }

                Spacer()
            }
            .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Layout.chatMessageSpacing) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageRow(message: message, compact: true)
                                .id(message.id)
                        }

                        if viewModel.isResponding {
                            FridayTypingRow()
                                .id("fridayTyping")
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .onChange(of: viewModel.messages) { _, messages in
                    guard let lastMessage = messages.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isResponding) { _, isResponding in
                    guard isResponding else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("fridayTyping", anchor: .bottom)
                    }
                }
            }

            PromptField(
                text: $viewModel.prompt,
                placeholder: "Tell Friday what to do next",
                isFocused: $isPromptFocused,
                namespace: namespace,
                matchedGeometryID: "browserFridayPrompt",
                onSubmit: viewModel.sendPrompt
            )
        }
        .padding(Layout.browserChatPadding)
        .frame(width: Layout.browserChatWidth, height: Layout.panelHeight)
        .glassSurface(cornerRadius: Layout.panelCornerRadius)
        .onAppear {
            isPromptFocused = true
        }
    }
}

private struct FridayWebView: NSViewRepresentable {
    @ObservedObject var session: FridayBrowserSession

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        session.attach(webView)
        context.coordinator.lastLoadedRequestID = session.requestID
        webView.load(URLRequest(url: session.requestedURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        session.attach(webView)
        guard context.coordinator.lastLoadedRequestID != session.requestID else { return }
        context.coordinator.lastLoadedRequestID = session.requestID
        webView.load(URLRequest(url: session.requestedURL))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let session: FridayBrowserSession
        var lastLoadedRequestID: UUID?

        init(session: FridayBrowserSession) {
            self.session = session
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            session.setLoading(true)
            session.updateVisibleURL(webView.url)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            session.updateVisibleURL(webView.url)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            session.updateVisibleURL(webView.url)
            session.setLoading(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            session.setLoading(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            session.setLoading(false)
        }
    }
}

private struct ChatMessageRow: View {
    let message: FridayPanelChatMessage
    var compact = false

    private let horizontalInset: CGFloat = 54

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: compact ? 18 : horizontalInset)
            }

            VStack(alignment: .leading, spacing: 10) {
                if isUser {
                    Text(message.text)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    FridayMarkdownView(markdown: message.text)
                }

                ForEach(message.mediaAttachments) { attachment in
                    GeneratedMediaAttachmentView(attachment: attachment)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(backgroundStyle, in: .rect(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(AppColor.white.opacity(isUser ? 0.16 : 0.1), lineWidth: 1)
            }

            if !isUser {
                Spacer(minLength: compact ? 18 : horizontalInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var backgroundStyle: Color {
        isUser ? AppColor.white.opacity(0.18) : AppColor.black.opacity(0.24)
    }
}

private struct FridayMarkdownView: View {
    let markdown: String

    private var blocks: [FridayMarkdownBlock] {
        FridayMarkdownParser.blocks(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: FridayMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(FridayMarkdownParser.inlineAttributedString(from: text))
                .font(headingFont(for: level))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 2 : 0)
        case .paragraph(let text):
            Text(FridayMarkdownParser.inlineAttributedString(from: text))
                .font(.callout)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        case .horizontalRule:
            Rectangle()
                .fill(AppColor.white.opacity(0.16))
                .frame(height: 1)
                .padding(.vertical, 4)
        case .table(let table):
            FridayMarkdownTableView(table: table)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            .title2.weight(.semibold)
        case 2:
            .title3.weight(.semibold)
        case 3:
            .headline.weight(.semibold)
        case 4:
            .subheadline.weight(.semibold)
        case 5:
            .callout.weight(.semibold)
        default:
            .caption.weight(.semibold)
        }
    }
}

private struct FridayMarkdownTableView: View {
    let table: FridayMarkdownTable

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                        tableCell(header, isHeader: true)
                    }
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<table.columnCount, id: \.self) { index in
                            tableCell(index < row.count ? row[index] : "", isHeader: false)
                        }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColor.white.opacity(0.14), lineWidth: 1)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func tableCell(_ markdown: String, isHeader: Bool) -> some View {
        Text(FridayMarkdownParser.inlineAttributedString(from: markdown))
            .font(isHeader ? .caption.weight(.semibold) : .caption)
            .foregroundStyle(.white.opacity(isHeader ? 0.94 : 0.84))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 92, maxWidth: 180, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppColor.black.opacity(isHeader ? 0.3 : 0.18))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AppColor.white.opacity(0.1))
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppColor.white.opacity(0.1))
                    .frame(height: 1)
            }
    }
}

private struct GeneratedMediaAttachmentView: View {
    let attachment: FridayGeneratedMediaAttachment

    @State private var isDownloadHovered = false
    @State private var isRevealHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if attachment.kind == .image, let image = NSImage(contentsOf: attachment.url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppColor.white.opacity(0.12), lineWidth: 1)
                    }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: attachment.kind.systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(AppColor.black.opacity(0.24), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.kind.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(attachment.url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: 8) {
                Text(attachment.url.lastPathComponent)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button(action: revealInFinder) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(AppColor.black.opacity(isRevealHovered ? 0.34 : 0.2), in: Circle())
                .cursor(.pointingHand)
                .onHover { isRevealHovered = $0 }
                .help("Show in Finder")

                Button(action: saveCopy) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(AppColor.black.opacity(isDownloadHovered ? 0.34 : 0.2), in: Circle())
                .cursor(.pointingHand)
                .onHover { isDownloadHovered = $0 }
                .help("Save a copy")
            }
        }
        .padding(8)
        .background(AppColor.black.opacity(0.18), in: .rect(cornerRadius: 13, style: .continuous))
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([attachment.url])
    }

    private func saveCopy() {
        guard let directory = FridayContextPicker.pickOutputDirectory() else { return }
        let destination = directory.appending(path: attachment.url.lastPathComponent, directoryHint: .notDirectory)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: attachment.url, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            NSLog("Friday failed to save generated media: \(error.localizedDescription)")
        }
    }
}

private struct FridayTypingRow: View {
    private let horizontalInset: CGFloat = 54

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(AppColor.white.opacity(0.72))
                        .frame(width: 5, height: 5)
                        .opacity(index == 1 ? 0.52 : 0.82)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(AppColor.black.opacity(0.24), in: .rect(cornerRadius: 15, style: .continuous))

            Spacer(minLength: horizontalInset)
        }
    }
}

private struct SidebarItem: Identifiable, Hashable {
    let systemName: String
    let title: String

    var id: String { title }
}

@MainActor
private final class FridayPanelChatViewModel: ObservableObject {
    @Published var prompt = ""
    @Published private(set) var messages: [FridayPanelChatMessage] = [
        FridayPanelChatMessage(
            role: .friday,
            text: "I’m Friday. Tell me what you’re working toward, and I’ll help you pick the next useful step."
        ),
    ]
    @Published private(set) var isResponding = false
    @Published private(set) var modelStatusText = "Ready"
    @Published private(set) var contextItems: [FridayContextItem] = []
    @Published private(set) var savedMemoryNotice: FridaySavedMemoryNotice?
    @Published private(set) var browserSession: FridayBrowserSession?

    private let store: FridayAssistantStore
    private let assistant: FridayPanelAssistantService

    init(store: FridayAssistantStore) {
        self.store = store
        assistant = FridayPanelAssistantService(store: store)
    }

    func start() {
        Task {
            modelStatusText = await assistant.statusText
            contextItems = store.contextItems
        }
    }

    func sendPrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !isResponding else {
            return
        }

        prompt = ""
        messages.append(FridayPanelChatMessage(role: .user, text: trimmedPrompt))

        if let browserRequest = FridayBrowserRequestDetector.request(from: trimmedPrompt) {
            openBrowser(for: browserRequest)
            return
        }

        if let browserSession, let command = FridayBrowserCommandDetector.command(from: trimmedPrompt) {
            performBrowserCommand(command, in: browserSession)
            return
        }

        if let browserSession {
            performBrowserAgentTask(trimmedPrompt, in: browserSession)
            return
        }

        isResponding = true
        modelStatusText = "Thinking"

        let conversation = messages

        Task {
            let response = await assistant.respond(to: trimmedPrompt, conversation: conversation)
            finishResponse(response)
        }
    }

    private func finishResponse(_ response: FridayPanelAssistantResponse) {
        messages.append(
            FridayPanelChatMessage(
                role: .friday,
                text: response.text,
                mediaAttachments: response.mediaAttachments
            )
        )
        if let savedMemory = response.savedMemory {
            savedMemoryNotice = FridaySavedMemoryNotice(memoryID: savedMemory.id, text: savedMemory.text)
        }
        isResponding = false
        modelStatusText = response.statusText
    }

    func undoLastMemorySave() {
        guard let notice = savedMemoryNotice else { return }
        store.deleteMemory(id: notice.memoryID)
        self.savedMemoryNotice = nil
    }

    func openFolderContext() {
        guard let url = FridayContextPicker.pickFolder() else { return }
        attachContext(from: [url])
    }

    func openFileContext() {
        let urls = FridayContextPicker.pickFiles()
        guard !urls.isEmpty else { return }
        attachContext(from: urls)
    }

    func closeBrowser() {
        browserSession = nil
    }

    private func openBrowser(for request: FridayBrowserRequest) {
        if let existingSession = browserSession {
            existingSession.navigate(to: request.url, userRequest: request.originalText)
            messages.append(
                FridayPanelChatMessage(
                    role: .friday,
                    text: "Navigating the main glass to \(request.displayName). I’ll update the browser header from the page that actually loads."
                )
            )
        } else {
            browserSession = FridayBrowserSession(url: request.url, userRequest: request.originalText)
            messages.append(
                FridayPanelChatMessage(
                    role: .friday,
                    text: "I opened \(request.displayName) in the main glass. I can help you navigate it here. For purchases, orders, payments, or anything externally visible, I’ll ask you to confirm before the final action."
                )
            )
        }
        modelStatusText = "Browser"
    }

    private func performBrowserCommand(_ command: FridayBrowserCommand, in session: FridayBrowserSession) {
        modelStatusText = "Using browser"

        Task {
            let result = await session.perform(command)
            messages.append(FridayPanelChatMessage(role: .friday, text: result.message))
            modelStatusText = "Browser"
        }
    }

    private func performBrowserAgentTask(_ task: String, in session: FridayBrowserSession) {
        isResponding = true
        modelStatusText = "Browser agent"

        let settings = store.snapshot().settings

        Task {
            let result = await FridayBrowserAgent(settings: settings).run(task: task, session: session)
            messages.append(FridayPanelChatMessage(role: .friday, text: result.message))
            isResponding = false
            modelStatusText = result.didNeedConfirmation ? "Needs confirmation" : "Browser"
        }
    }

    private func attachContext(from urls: [URL]) {
        modelStatusText = "Reading context"

        Task {
            let items = await FridayContextReader.items(for: urls)
            store.addContext(items)
            contextItems = store.contextItems
            modelStatusText = await assistant.statusText
        }
    }
}

private actor FridayPanelAssistantService {
    private let store: FridayAssistantStore

    init(store: FridayAssistantStore) {
        self.store = store
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func session(settings: FridayAssistantSettings) -> LanguageModelSession {
        let signature = settings.instructionSignature
        if let existingSession, existingSessionSignature == signature {
            return existingSession
        }

        let session = LanguageModelSession(instructions: instructions(settings: settings))
        existingSession = session
        existingSessionSignature = signature
        return session
    }

    @available(macOS 26.0, *)
    private var existingSession: LanguageModelSession?
    private var existingSessionSignature: String?
    #endif

    var statusText: String {
        get async {
            let snapshot = await MainActor.run { store.snapshot() }

            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                if case .available = SystemLanguageModel.default.availability {
                    return snapshot.settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Apple Intelligence"
                        : "OpenAI"
                }
            }
            #endif

            return snapshot.settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Needs API key"
                : "OpenAI"
        }
    }

    func respond(
        to message: String,
        conversation: [FridayPanelChatMessage]
    ) async -> FridayPanelAssistantResponse {
        let snapshot = await MainActor.run { store.snapshot() }
        let relevantMemories = snapshot.relevantMemories(for: message)

        if let openAIResponse = await OpenAIClient(settings: snapshot.settings).respond(
            to: message,
            conversation: conversation,
            memories: relevantMemories,
            contextItems: snapshot.contextItems
        ) {
            let savedMemory = await classifyAndSaveMemory(
                userMessage: message,
                assistantMessage: openAIResponse.text,
                conversation: conversation,
                snapshot: snapshot
            )
            return openAIResponse.withSavedMemory(savedMemory)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                return unavailableResponse
            }

            do {
                let response = try await session(settings: snapshot.settings).respond(
                    to: prompt(
                        for: message,
                        conversation: conversation,
                        snapshot: snapshot,
                        relevantMemories: relevantMemories
                    )
                )

                let responseText = response.content
                let savedMemory = await classifyAndSaveMemory(
                    userMessage: message,
                    assistantMessage: responseText,
                    conversation: conversation,
                    snapshot: snapshot
                )

                return FridayPanelAssistantResponse(
                    text: responseText,
                    statusText: "Apple Intelligence",
                    savedMemory: savedMemory
                )
            } catch {
                return FridayPanelAssistantResponse(
                    text: "Apple Intelligence could not answer that just now: \(error.localizedDescription)",
                    statusText: "Apple Intelligence unavailable"
                )
            }
        }
        #endif

        return unavailableResponse
    }

    private func classifyAndSaveMemory(
        userMessage: String,
        assistantMessage: String,
        conversation: [FridayPanelChatMessage],
        snapshot: FridayAssistantSnapshot
    ) async -> FridayMemoryRecord? {
        let candidate = await FridayMemoryClassifier(settings: snapshot.settings).candidate(
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            conversation: conversation,
            existingMemories: snapshot.memories
        )

        guard let candidate, candidate.shouldSave else {
            return nil
        }

        let result = await MainActor.run {
            store.upsertMemory(candidate)
        }

        return result.didInsert ? result.record : nil
    }

    private var unavailableResponse: FridayPanelAssistantResponse {
        FridayPanelAssistantResponse(
            text: "Add an OpenAI API key in Settings so I can give useful assistant responses here. Apple Intelligence is not available on this Mac right now.",
            statusText: "Needs API key"
        )
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func instructions(settings: FridayAssistantSettings) -> String {
        let behaviorPrompt = settings.behaviorPrompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        return """
        You are Friday, the user's personal AI assistant. Help the user achieve their goals.
        Give intelligent, contextual responses, not canned scripts. Be direct, concise, and practical.
        When the user asks what to do, recommend one concrete next focus item with a reason and a first step.
        Distinguish known facts from guesses. Do not claim to have read full email or calendar details unless they are provided.
        Do not say you changed calendar events, sent email, or completed external actions.
        \(behaviorPrompt.isEmpty ? "" : "\nUser custom behavior instructions:\n\(behaviorPrompt)")
        """
    }

    private func prompt(
        for message: String,
        conversation: [FridayPanelChatMessage],
        snapshot: FridayAssistantSnapshot,
        relevantMemories: [FridayMemoryRecord]
    ) -> String {
        let transcript = conversation.suffix(10)
            .map { "\($0.role.transcriptName): \($0.text)" }
            .joined(separator: "\n")

        return """
        Current date: \(Date().formatted(date: .abbreviated, time: .shortened))
        Mood: \(snapshot.settings.mood.rawValue)
        Custom behavior instructions:
        \(snapshot.settings.behaviorPrompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))

        Relevant saved memory:
        \(relevantMemories.map { "- [\($0.category.rawValue)] \($0.text)" }.joined(separator: "\n"))

        User-provided context:
        \(snapshot.contextItems.prefix(8).map { "- \($0.title): \($0.preview)" }.joined(separator: "\n\n"))

        Conversation so far:
        \(transcript)

        User's latest message:
        \(message)
        """
    }
    #endif
}

private nonisolated struct FridayPanelAssistantResponse: Equatable {
    let text: String
    let statusText: String
    let savedMemory: FridayMemoryRecord?
    let mediaAttachments: [FridayGeneratedMediaAttachment]

    init(
        text: String,
        statusText: String,
        savedMemory: FridayMemoryRecord? = nil,
        mediaAttachments: [FridayGeneratedMediaAttachment] = []
    ) {
        self.text = text
        self.statusText = statusText
        self.savedMemory = savedMemory
        self.mediaAttachments = mediaAttachments
    }

    func withSavedMemory(_ memory: FridayMemoryRecord?) -> FridayPanelAssistantResponse {
        FridayPanelAssistantResponse(
            text: text,
            statusText: statusText,
            savedMemory: memory,
            mediaAttachments: mediaAttachments
        )
    }
}

private nonisolated struct FridaySavedMemoryNotice: Equatable {
    let memoryID: UUID
    let text: String
}

private struct FridayPanelChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: FridayPanelChatRole
    let text: String
    let mediaAttachments: [FridayGeneratedMediaAttachment]

    init(
        id: UUID = UUID(),
        role: FridayPanelChatRole,
        text: String,
        mediaAttachments: [FridayGeneratedMediaAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.mediaAttachments = mediaAttachments
    }
}

private nonisolated enum FridayPanelChatRole: Equatable {
    case user
    case friday

    var transcriptName: String {
        switch self {
        case .user:
            "User"
        case .friday:
            "Friday"
        }
    }
}

@MainActor
private final class FridayBrowserSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var requestedURL: URL
    @Published private(set) var visibleURL: URL?
    @Published private(set) var userRequest: String
    @Published private(set) var requestID = UUID()
    @Published private(set) var isLoading = false

    private weak var webView: WKWebView?

    init(url: URL, userRequest: String) {
        self.requestedURL = url
        self.visibleURL = url
        self.userRequest = userRequest
    }

    var displayHost: String {
        let url = visibleURL ?? requestedURL
        return url.host(percentEncoded: false) ?? url.absoluteString
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func navigate(to url: URL, userRequest: String) {
        self.requestedURL = url
        self.userRequest = userRequest
        self.requestID = UUID()
        self.isLoading = true
        webView?.load(URLRequest(url: url))
    }

    func reload() {
        webView?.reload()
    }

    func updateVisibleURL(_ url: URL?) {
        guard let url, visibleURL != url else { return }
        visibleURL = url
    }

    func setLoading(_ isLoading: Bool) {
        self.isLoading = isLoading
    }

    func perform(_ command: FridayBrowserCommand) async -> FridayBrowserCommandResult {
        guard webView != nil else {
            return FridayBrowserCommandResult(message: "The browser is still loading. Try that again in a moment.")
        }

        do {
            let didComplete = try await evaluateBooleanJavaScript(command.javaScript)
            if didComplete {
                return FridayBrowserCommandResult(message: command.successMessage)
            }

            return FridayBrowserCommandResult(message: command.failureMessage)
        } catch {
            return FridayBrowserCommandResult(message: "I could not complete that browser action: \(error.localizedDescription)")
        }
    }

    func pageSnapshot() async -> FridayBrowserPageSnapshot {
        guard webView != nil else {
            return FridayBrowserPageSnapshot(url: visibleURL ?? requestedURL, title: "", text: "", controls: [])
        }

        do {
            let value = try await evaluateJavaScript(Self.pageSnapshotJavaScript)
            guard let object = value as? [String: Any] else {
                return FridayBrowserPageSnapshot(url: visibleURL ?? requestedURL, title: "", text: "", controls: [])
            }

            let controls = (object["controls"] as? [[String: Any]] ?? []).compactMap { item -> FridayBrowserPageControl? in
                guard let label = item["label"] as? String, !label.isEmpty else { return nil }
                return FridayBrowserPageControl(
                    index: item["index"] as? Int ?? 0,
                    kind: item["kind"] as? String ?? "control",
                    label: label.prefixString(120)
                )
            }

            return FridayBrowserPageSnapshot(
                url: visibleURL ?? requestedURL,
                title: object["title"] as? String ?? "",
                text: (object["text"] as? String ?? "").prefixString(1800),
                controls: controls
            )
        } catch {
            return FridayBrowserPageSnapshot(url: visibleURL ?? requestedURL, title: "", text: "", controls: [])
        }
    }

    func waitForPageSettled() async {
        try? await Task.sleep(for: .milliseconds(900))
    }

    private func evaluateBooleanJavaScript(_ javaScript: String) async throws -> Bool {
        let value = try await evaluateJavaScript(javaScript)
        return (value as? Bool) == true
    }

    private func evaluateJavaScript(_ javaScript: String) async throws -> Any? {
        guard let webView else { return false }

        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(javaScript) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: value)
            }
        }
    }

    private static let pageSnapshotJavaScript = """
    (() => {
      const visible = (element) => {
        const rect = element.getBoundingClientRect();
        const style = window.getComputedStyle(element);
        return rect.width > 0 && rect.height > 0 && rect.bottom >= 0 && rect.top <= window.innerHeight && style.visibility !== 'hidden' && style.display !== 'none';
      };
      const clean = (value) => (value || '').replace(/\\s+/g, ' ').trim();
      const label = (element) => clean([
        element.innerText,
        element.value,
        element.getAttribute('aria-label'),
        element.getAttribute('title'),
        element.getAttribute('placeholder'),
        element.name,
        element.id
      ].filter(Boolean).join(' '));
      const nodes = Array.from(document.querySelectorAll('a, button, [role="button"], input, textarea, select, summary, [onclick]'));
      const controls = nodes
        .filter(visible)
        .map((element, index) => ({
          index,
          kind: (element.tagName || '').toLowerCase() + (element.getAttribute('role') ? ':' + element.getAttribute('role') : ''),
          label: label(element).slice(0, 160)
        }))
        .filter(item => item.label.length > 0)
        .slice(0, 80);
      return {
        title: document.title || '',
        text: clean(document.body ? document.body.innerText : '').slice(0, 2500),
        controls
      };
    })();
    """
}

private nonisolated struct FridayBrowserCommandResult: Equatable {
    let message: String
}

private nonisolated struct FridayBrowserPageSnapshot: Equatable {
    let url: URL
    let title: String
    let text: String
    let controls: [FridayBrowserPageControl]

    var promptText: String {
        """
        URL: \(url.absoluteString)
        Title: \(title)

        Visible page text:
        \(text)

        Visible controls:
        \(controls.prefix(60).map { "- [\($0.index)] \($0.kind): \($0.label)" }.joined(separator: "\n"))
        """
    }
}

private nonisolated struct FridayBrowserPageControl: Equatable {
    let index: Int
    let kind: String
    let label: String
}

private struct FridayBrowserAgent {
    let settings: FridayAssistantSettings

    func run(task: String, session: FridayBrowserSession) async -> FridayBrowserAgentResult {
        let apiKey = settings.apiKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return FridayBrowserAgentResult(
                message: "Add your OpenAI API key in Settings so I can operate the browser agentically. I can still follow direct commands like `click \"Add to Cart\"`.",
                didNeedConfirmation: false
            )
        }

        var actionLog: [String] = []

        for _ in 0..<8 {
            await session.waitForPageSettled()
            let snapshot = await session.pageSnapshot()

            guard let action = await nextAction(task: task, snapshot: snapshot, actionLog: actionLog, apiKey: apiKey) else {
                return FridayBrowserAgentResult(
                    message: "I could not decide the next browser step from the visible page. Try a more specific instruction, or tell me exactly what to click/type.",
                    didNeedConfirmation: false
                )
            }

            switch action.kind {
            case .done:
                return FridayBrowserAgentResult(
                    message: action.message.isEmpty ? "Done." : action.message,
                    didNeedConfirmation: false
                )
            case .needsConfirmation:
                return FridayBrowserAgentResult(
                    message: action.message.isEmpty ? "I’m at a step that needs your confirmation before I continue." : action.message,
                    didNeedConfirmation: true
                )
            case .navigate:
                guard let url = action.url else {
                    actionLog.append("Navigate failed: missing URL")
                    continue
                }
                await MainActor.run {
                    session.navigate(to: url, userRequest: task)
                }
                actionLog.append("Navigated to \(url.absoluteString)")
            case .click:
                let command: FridayBrowserCommand
                if let index = action.index {
                    command = .clickIndex(index)
                } else if let text = action.text, !text.isEmpty {
                    command = .click(text)
                } else {
                    actionLog.append("Click failed: missing target")
                    continue
                }
                let result = await session.perform(command)
                actionLog.append(result.message)
            case .type:
                guard let text = action.text, !text.isEmpty else {
                    actionLog.append("Type failed: missing text")
                    continue
                }
                let result = await session.perform(.type(text))
                actionLog.append(result.message)
            case .search:
                guard let text = action.text, !text.isEmpty else {
                    actionLog.append("Search failed: missing text")
                    continue
                }
                let result = await session.perform(.search(text))
                actionLog.append(result.message)
            case .pressEnter:
                let result = await session.perform(.pressEnter)
                actionLog.append(result.message)
            }
        }

        return FridayBrowserAgentResult(
            message: "I made progress, but I hit my step limit. Current actions: \(actionLog.suffix(4).joined(separator: " "))",
            didNeedConfirmation: false
        )
    }

    private func nextAction(
        task: String,
        snapshot: FridayBrowserPageSnapshot,
        actionLog: [String],
        apiKey: String
    ) async -> FridayBrowserAgentAction? {
        do {
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": settings.model,
                "max_output_tokens": 320,
                "instructions": instructions,
                "input": """
                User browser task:
                \(task)

                Page snapshot:
                \(snapshot.promptText)

                Actions already taken:
                \(actionLog.suffix(10).joined(separator: "\n"))

                Return exactly one JSON object.
                """,
            ] as [String: Any])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            let text = OpenAIClient.extractText(from: data)
            return FridayBrowserAgentAction.decode(from: text)
        } catch {
            return nil
        }
    }

    private var instructions: String {
        """
        You are Friday's browser-control planner. Pick exactly one next browser action.
        Use only the visible page snapshot. Do not claim success unless the page shows it.
        Prefer control indexes when clicking because they are tied to the visible page.
        You may help with shopping tasks, including searching products and adding items to cart.
        You must stop and ask for confirmation before checkout, payment, placing an order, sending a message/email, deleting data, booking, or any irreversible/external final action.

        Return exactly one JSON object with one of:
        {"action":"click","index":12,"text":"optional label","message":"short progress note"}
        {"action":"type","text":"text to type","message":"short progress note"}
        {"action":"search","text":"query","message":"short progress note"}
        {"action":"press_enter","message":"short progress note"}
        {"action":"navigate","url":"https://example.com","message":"short progress note"}
        {"action":"needs_confirmation","message":"Ask user to confirm the exact final action."}
        {"action":"done","message":"Briefly say what is done and what is visible."}
        """
    }
}

private nonisolated struct FridayBrowserAgentResult: Equatable {
    let message: String
    let didNeedConfirmation: Bool
}

private nonisolated struct FridayBrowserAgentAction: Equatable {
    let kind: Kind
    let index: Int?
    let text: String?
    let url: URL?
    let message: String

    enum Kind: Equatable {
        case click
        case type
        case search
        case pressEnter
        case navigate
        case needsConfirmation
        case done
    }

    static func decode(from text: String) -> FridayBrowserAgentAction? {
        let jsonText = text
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .strippingMarkdownCodeFence
        guard
            let data = jsonText.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let action = object["action"] as? String
        else {
            return nil
        }

        let kind: Kind
        switch action {
        case "click":
            kind = .click
        case "type":
            kind = .type
        case "search":
            kind = .search
        case "press_enter":
            kind = .pressEnter
        case "navigate":
            kind = .navigate
        case "needs_confirmation":
            kind = .needsConfirmation
        case "done":
            kind = .done
        default:
            return nil
        }

        let url = (object["url"] as? String).flatMap(URL.init(string:))
        return FridayBrowserAgentAction(
            kind: kind,
            index: object["index"] as? Int,
            text: object["text"] as? String,
            url: url,
            message: object["message"] as? String ?? ""
        )
    }
}

private nonisolated enum FridayBrowserCommand: Equatable {
    case click(String)
    case clickIndex(Int)
    case type(String)
    case search(String)
    case pressEnter

    var javaScript: String {
        switch self {
        case .click(let text):
            """
            (() => {
              const needle = \(Self.javaScriptString(text)).toLowerCase();
              const visible = (element) => {
                const rect = element.getBoundingClientRect();
                const style = window.getComputedStyle(element);
                return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
              };
              const label = (element) => [
                element.innerText,
                element.value,
                element.getAttribute('aria-label'),
                element.getAttribute('title'),
                element.getAttribute('placeholder')
              ].filter(Boolean).join(' ').toLowerCase();
              const candidates = Array.from(document.querySelectorAll('a, button, [role="button"], input[type="submit"], input[type="button"], summary, [onclick]'));
              const element = candidates.find((candidate) => visible(candidate) && label(candidate).includes(needle));
              if (!element) { return false; }
              element.scrollIntoView({ block: 'center', inline: 'center' });
              element.click();
              return true;
            })();
            """
        case .clickIndex(let index):
            """
            (() => {
              const targetIndex = \(index);
              const visible = (element) => {
                const rect = element.getBoundingClientRect();
                const style = window.getComputedStyle(element);
                return rect.width > 0 && rect.height > 0 && rect.bottom >= 0 && rect.top <= window.innerHeight && style.visibility !== 'hidden' && style.display !== 'none';
              };
              const nodes = Array.from(document.querySelectorAll('a, button, [role="button"], input, textarea, select, summary, [onclick]')).filter(visible);
              const element = nodes[targetIndex];
              if (!element) { return false; }
              element.scrollIntoView({ block: 'center', inline: 'center' });
              element.focus();
              element.click();
              return true;
            })();
            """
        case .type(let text):
            """
            (() => {
              const value = \(Self.javaScriptString(text));
              const editable = (element) => element && (
                element.tagName === 'TEXTAREA' ||
                element.isContentEditable ||
                (element.tagName === 'INPUT' && !['button','submit','checkbox','radio','hidden'].includes((element.type || '').toLowerCase()))
              );
              let element = editable(document.activeElement) ? document.activeElement : null;
              if (!element) {
                element = Array.from(document.querySelectorAll('input[type="search"], input[type="text"], input:not([type]), textarea, [contenteditable="true"]'))
                  .find((candidate) => candidate.offsetWidth > 0 && candidate.offsetHeight > 0);
              }
              if (!element) { return false; }
              element.focus();
              if (element.isContentEditable) {
                element.textContent = value;
              } else {
                element.value = value;
              }
              element.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: value }));
              element.dispatchEvent(new Event('change', { bubbles: true }));
              return true;
            })();
            """
        case .search(let text):
            """
            (() => {
              const value = \(Self.javaScriptString(text));
              const element = Array.from(document.querySelectorAll('input[type="search"], input[name="q"], input[type="text"], input:not([type]), textarea'))
                .find((candidate) => candidate.offsetWidth > 0 && candidate.offsetHeight > 0);
              if (!element) { return false; }
              element.focus();
              element.value = value;
              element.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: value }));
              const form = element.form || element.closest('form');
              if (form) {
                form.requestSubmit ? form.requestSubmit() : form.submit();
              } else {
                element.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true }));
              }
              return true;
            })();
            """
        case .pressEnter:
            """
            (() => {
              const element = document.activeElement;
              if (!element) { return false; }
              const form = element.form || element.closest('form');
              if (form) {
                form.requestSubmit ? form.requestSubmit() : form.submit();
                return true;
              }
              element.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true }));
              element.dispatchEvent(new KeyboardEvent('keyup', { key: 'Enter', code: 'Enter', bubbles: true }));
              return true;
            })();
            """
        }
    }

    var successMessage: String {
        switch self {
        case .click(let text):
            "I clicked “\(text)” on the page."
        case .clickIndex(let index):
            "I clicked control \(index) on the page."
        case .type(let text):
            "I typed “\(text)” into the active field."
        case .search(let text):
            "I searched for “\(text)” on the page."
        case .pressEnter:
            "I pressed Enter on the page."
        }
    }

    var failureMessage: String {
        switch self {
        case .click(let text):
            "I could not find a visible clickable control matching “\(text)”."
        case .clickIndex(let index):
            "I could not find visible control \(index)."
        case .type:
            "I could not find a visible text field to type into."
        case .search:
            "I could not find a visible search field on this page."
        case .pressEnter:
            "I could not find an active page element to press Enter on."
        }
    }

    private static func javaScriptString(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value]),
            let string = String(data: data, encoding: .utf8),
            string.count >= 2
        else {
            return "\"\""
        }

        return String(string.dropFirst().dropLast())
    }
}

private nonisolated enum FridayBrowserCommandDetector {
    static func command(from text: String) -> FridayBrowserCommand? {
        let trimmedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let lowercasedText = trimmedText.lowercased()

        if lowercasedText == "press enter" || lowercasedText == "hit enter" || lowercasedText == "submit" {
            return .pressEnter
        }

        if let value = quotedValue(in: trimmedText), lowercasedText.contains("click") || lowercasedText.contains("tap") || lowercasedText.contains("select") {
            return .click(value)
        }

        if let value = quotedValue(in: trimmedText), lowercasedText.contains("type") || lowercasedText.contains("enter") || lowercasedText.contains("fill") {
            return .type(value)
        }

        if let value = quotedValue(in: trimmedText), lowercasedText.contains("search") {
            return .search(value)
        }

        if let value = value(afterAny: ["click ", "tap ", "select "], in: trimmedText) {
            return .click(value)
        }

        if let value = value(afterAny: ["type ", "enter ", "fill "], in: trimmedText) {
            return .type(value)
        }

        if let value = value(afterAny: ["search for ", "search "], in: trimmedText) {
            return .search(value)
        }

        return nil
    }

    private static func quotedValue(in text: String) -> String? {
        let pattern = #""([^"]+)"|'([^']+)'|“([^”]+)”"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        else {
            return nil
        }

        for index in 1..<match.numberOfRanges {
            guard
                match.range(at: index).location != NSNotFound,
                let range = Range(match.range(at: index), in: text)
            else {
                continue
            }

            return String(text[range]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }

        return nil
    }

    private static func value(afterAny prefixes: [String], in text: String) -> String? {
        let lowercasedText = text.lowercased()
        for prefix in prefixes {
            guard let range = lowercasedText.range(of: prefix) else { continue }
            let value = text[range.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        return nil
    }
}

private nonisolated struct FridayBrowserRequest: Equatable {
    let url: URL
    let originalText: String

    var displayName: String {
        url.host(percentEncoded: false) ?? url.absoluteString
    }
}

private nonisolated enum FridayBrowserURLParser {
    static func url(from text: String) -> URL? {
        let trimmedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        if let url = URL(string: trimmedText), url.scheme != nil {
            return url
        }

        if trimmedText.contains(".") && !trimmedText.contains(" ") {
            return URL(string: "https://\(trimmedText)")
        }

        let query = trimmedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedText
        return URL(string: "https://www.google.com/search?q=\(query)")
    }
}

private nonisolated enum FridayBrowserRequestDetector {
    static func request(from text: String) -> FridayBrowserRequest? {
        let trimmedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard shouldUseBrowser(trimmedText) else { return nil }

        if let explicitURL = explicitURL(in: trimmedText) {
            return FridayBrowserRequest(url: explicitURL, originalText: trimmedText)
        }

        let lowercasedText = trimmedText.lowercased()
        if lowercasedText.contains("doordash") || lowercasedText.contains("door dash") {
            return FridayBrowserRequest(url: URL(string: "https://www.doordash.com/")!, originalText: trimmedText)
        }

        if lowercasedText.contains("uber eats") || lowercasedText.contains("ubereats") {
            return FridayBrowserRequest(url: URL(string: "https://www.ubereats.com/")!, originalText: trimmedText)
        }

        if lowercasedText.contains("amazon") {
            return FridayBrowserRequest(url: URL(string: "https://www.amazon.com/")!, originalText: trimmedText)
        }

        if lowercasedText.contains("google") {
            return FridayBrowserRequest(url: URL(string: "https://www.google.com/search?q=\(queryComponent(from: trimmedText))")!, originalText: trimmedText)
        }

        if lowercasedText.contains("search") || lowercasedText.contains("look up") || lowercasedText.contains("find ") {
            return FridayBrowserRequest(url: URL(string: "https://www.google.com/search?q=\(queryComponent(from: trimmedText))")!, originalText: trimmedText)
        }

        return FridayBrowserRequest(url: URL(string: "https://www.google.com/search?q=\(queryComponent(from: trimmedText))")!, originalText: trimmedText)
    }

    private static func shouldUseBrowser(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()

        if explicitURL(in: text) != nil {
            return true
        }

        return [
            "open browser",
            "open a browser",
            "open website",
            "go to ",
            "look at ",
            "look up ",
            "search web",
            "search online",
            "website",
            "doordash",
            "door dash",
            "order food",
            "uber eats",
            "amazon",
        ].contains { lowercasedText.contains($0) }
    }

    private static func explicitURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector?.firstMatch(in: text, options: [], range: range), let url = match.url else {
            return domainURL(in: text)
        }

        return normalizedURL(url)
    }

    private static func domainURL(in text: String) -> URL? {
        let pattern = #"(?i)\b(?:[a-z0-9-]+\.)+[a-z]{2,}(?:/[^\s]*)?\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
            let range = Range(match.range, in: text)
        else {
            return nil
        }

        let value = String(text[range])
        return FridayBrowserURLParser.url(from: value)
    }

    private static func queryComponent(from text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }

    private static func normalizedURL(_ url: URL) -> URL {
        if url.scheme == nil {
            return FridayBrowserURLParser.url(from: url.absoluteString) ?? url
        }

        return url
    }
}

private nonisolated struct FridayGeneratedMediaAttachment: Identifiable, Equatable {
    let id: UUID
    let kind: FridayGeneratedMediaKind
    let url: URL
    let prompt: String

    init(
        id: UUID = UUID(),
        kind: FridayGeneratedMediaKind,
        url: URL,
        prompt: String
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.prompt = prompt
    }
}

private nonisolated enum FridayGeneratedMediaKind: Equatable {
    case image
    case video

    var fileExtension: String {
        switch self {
        case .image:
            "png"
        case .video:
            "mp4"
        }
    }

    var systemName: String {
        switch self {
        case .image:
            "photo"
        case .video:
            "film"
        }
    }

    var title: String {
        switch self {
        case .image:
            "Generated image"
        case .video:
            "Generated video"
        }
    }
}

private nonisolated enum FridayMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case horizontalRule
    case table(FridayMarkdownTable)
}

private nonisolated struct FridayMarkdownTable: Equatable {
    let headers: [String]
    let rows: [[String]]

    var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }
}

private nonisolated enum FridayMarkdownParser {
    static func blocks(from markdown: String) -> [FridayMarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [FridayMarkdownBlock] = []
        var paragraphLines: [String] = []
        var index = 0

        func flushParagraph() {
            let text = paragraphLines
                .joined(separator: "\n")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmedLine = line.trimmingCharacters(in: CharacterSet.whitespaces)

            if trimmedLine.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if isHorizontalRule(trimmedLine) {
                flushParagraph()
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            if let heading = heading(from: trimmedLine) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if let table = table(from: lines, startingAt: index) {
                flushParagraph()
                blocks.append(.table(table.value))
                index = table.nextIndex
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    static func inlineAttributedString(from markdown: String) -> AttributedString {
        let underlineRanges = underlinedRanges(in: markdown)
        let markdownWithoutUnderline = markdown
            .replacingOccurrences(of: "<u>", with: "")
            .replacingOccurrences(of: "</u>", with: "")

        var attributed = (
            try? AttributedString(
                markdown: markdownWithoutUnderline,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        ) ?? AttributedString(markdownWithoutUnderline)

        for plainRange in underlineRanges {
            guard
                plainRange.lowerBound <= attributed.characters.count,
                plainRange.upperBound <= attributed.characters.count
            else {
                continue
            }

            let start = attributed.characters.index(attributed.startIndex, offsetBy: plainRange.lowerBound)
            let end = attributed.characters.index(attributed.startIndex, offsetBy: plainRange.upperBound)
            attributed[start..<end].underlineStyle = .single
        }

        return attributed
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            if character == "#", level < 6 {
                level += 1
            } else {
                break
            }
        }

        guard level > 0, line.dropFirst(level).first == " " else {
            return nil
        }

        return (level, String(line.dropFirst(level + 1)))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact.count >= 3 && Set(compact).isSubset(of: Set<Character>(["-", "*", "_"]))
    }

    private static func table(from lines: [String], startingAt startIndex: Int) -> (value: FridayMarkdownTable, nextIndex: Int)? {
        guard startIndex + 1 < lines.count else { return nil }

        let header = tableCells(from: lines[startIndex])
        let separator = tableCells(from: lines[startIndex + 1])
        guard header.count >= 2, separator.count == header.count, separator.allSatisfy(isTableSeparatorCell) else {
            return nil
        }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count {
            let row = tableCells(from: lines[index])
            guard row.count >= 2 else { break }
            rows.append(row)
            index += 1
        }

        return (FridayMarkdownTable(headers: header, rows: rows), index)
    }

    private static func tableCells(from line: String) -> [String] {
        let trimmedLine = line.trimmingCharacters(in: CharacterSet.whitespaces)
        guard trimmedLine.contains("|") else { return [] }

        let withoutOuterPipes = trimmedLine.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return withoutOuterPipes
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
    }

    private static func isTableSeparatorCell(_ cell: String) -> Bool {
        let compact = cell.replacingOccurrences(of: " ", with: "")
        let strippedAlignment = compact.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return strippedAlignment.count >= 3 && strippedAlignment.allSatisfy { $0 == "-" }
    }

    private static func underlinedRanges(in markdown: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var outputOffset = 0
        var searchIndex = markdown.startIndex

        while searchIndex < markdown.endIndex {
            if markdown[searchIndex...].hasPrefix("<u>") {
                let contentStart = markdown.index(searchIndex, offsetBy: 3)
                if let closeRange = markdown[contentStart...].range(of: "</u>") {
                    let content = markdown[contentStart..<closeRange.lowerBound]
                    let length = content.count
                    ranges.append(outputOffset..<(outputOffset + length))
                    outputOffset += length
                    searchIndex = closeRange.upperBound
                    continue
                }
            }

            outputOffset += 1
            searchIndex = markdown.index(after: searchIndex)
        }

        return ranges
    }
}

@MainActor
private final class FridayAssistantStore: ObservableObject {
    @Published var settings: FridayAssistantSettings {
        didSet {
            FridayKeychain.openAIAPIKey = settings.apiKey
            save()
        }
    }
    @Published private(set) var memories: [FridayMemoryRecord]
    @Published private(set) var contextItems: [FridayContextItem]

    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Friday", directoryHint: .isDirectory)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Friday", directoryHint: .isDirectory)

        fileURL = baseURL.appending(path: "assistant-state.json", directoryHint: .notDirectory)

        if
            let data = try? Data(contentsOf: fileURL),
            let state = try? JSONDecoder.fridayAssistant.decode(FridayAssistantState.self, from: data)
        {
            settings = state.settings
            memories = state.memories
            contextItems = state.contextItems
        } else {
            settings = FridayAssistantSettings()
            memories = []
            contextItems = []
        }

        FridayKeychain.openAIAPIKey = settings.apiKey
    }

    @discardableResult
    func upsertMemory(_ candidate: FridayMemoryCandidate) -> FridayMemoryUpsertResult {
        let now = Date()

        if let index = memories.firstIndex(where: { $0.matches(candidate) }) {
            let existing = memories[index]
            let merged = existing.updated(with: candidate, at: now)
            memories[index] = merged
            save()
            return FridayMemoryUpsertResult(record: merged, didInsert: false)
        }

        let record = FridayMemoryRecord(candidate: candidate, now: now)
        memories.insert(record, at: 0)
        memories = Array(memories.prefix(160))
        save()
        return FridayMemoryUpsertResult(record: record, didInsert: true)
    }

    func addContext(_ items: [FridayContextItem]) {
        guard !items.isEmpty else { return }

        var mergedItems = contextItems
        for item in items where !mergedItems.contains(where: { $0.source == item.source }) {
            mergedItems.insert(item, at: 0)
        }

        contextItems = Array(mergedItems.prefix(16))
        save()
    }

    func clearContext() {
        contextItems = []
        save()
    }

    func clearMemory() {
        memories = []
        save()
    }

    func deleteMemory(id: UUID) {
        memories.removeAll { $0.id == id }
        save()
    }

    func undoLastSave() {
        guard let memoryID = memories.first?.id else { return }
        deleteMemory(id: memoryID)
    }

    func snapshot() -> FridayAssistantSnapshot {
        FridayAssistantSnapshot(
            settings: settings,
            memories: memories,
            contextItems: contextItems
        )
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let state = FridayAssistantState(
                settings: settings,
                memories: memories,
                contextItems: contextItems
            )
            let data = try JSONEncoder.fridayAssistant.encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("Friday failed to save assistant state: \(error.localizedDescription)")
        }
    }

}

private nonisolated struct FridayMemoryUpsertResult: Equatable {
    let record: FridayMemoryRecord
    let didInsert: Bool
}

private nonisolated struct FridayAssistantSnapshot: Equatable {
    let settings: FridayAssistantSettings
    let memories: [FridayMemoryRecord]
    let contextItems: [FridayContextItem]

    func relevantMemories(for prompt: String, limit: Int = 12) -> [FridayMemoryRecord] {
        memories
            .filter { !$0.isExpired }
            .map { ($0, $0.relevanceScore(for: prompt)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.updatedAt > rhs.0.updatedAt
                }

                return lhs.1 > rhs.1
            }
            .prefix(limit)
            .map(\.0)
    }
}

private nonisolated struct FridayAssistantState: Codable {
    var settings: FridayAssistantSettings
    var memories: [FridayMemoryRecord]
    var contextItems: [FridayContextItem]
}

private nonisolated struct FridayAssistantSettings: Codable, Equatable {
    var apiKey = FridayKeychain.openAIAPIKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    var model = "gpt-5.4-mini"
    var mood = FridayAssistantMood.friendly
    var behaviorPrompt = ""

    enum CodingKeys: String, CodingKey {
        case apiKey
        case behaviorPrompt
        case model
        case mood
    }

    init() {}

    var instructionSignature: String {
        "\(mood.rawValue)\n\(behaviorPrompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "gpt-5.4-mini"
        mood = try container.decodeIfPresent(FridayAssistantMood.self, forKey: .mood) ?? .friendly
        behaviorPrompt = try container.decodeIfPresent(String.self, forKey: .behaviorPrompt) ?? ""
        let legacyAPIKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        apiKey = FridayKeychain.openAIAPIKey ?? legacyAPIKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(behaviorPrompt, forKey: .behaviorPrompt)
        try container.encode(model, forKey: .model)
        try container.encode(mood, forKey: .mood)
    }
}

private nonisolated enum FridayKeychain {
    private static let service = "com.vedpanse.Friday"
    private static let openAIAccount = "openai-api-key"

    static var openAIAPIKey: String? {
        get {
            read(account: openAIAccount)
        }
        set {
            save(newValue, account: openAIAccount)
        }
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }

        guard let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String?, account: String) {
        let trimmedValue = value?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

        guard !trimmedValue.isEmpty else {
            delete(account: account)
            return
        }

        let data = Data(trimmedValue.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

private nonisolated enum FridayAssistantMood: String, CaseIterable, Codable, Identifiable {
    case concise = "Concise"
    case friendly = "Friendly"
    case coach = "Coach"
    case calm = "Calm"

    var id: String { rawValue }

    var instruction: String {
        switch self {
        case .concise:
            "Be terse, practical, and direct. No filler."
        case .friendly:
            "Be warm and friendly, but still brief and useful."
        case .coach:
            "Be encouraging and goal-oriented. Push for concrete next actions."
        case .calm:
            "Be calm, grounding, and low-pressure. Reduce overwhelm."
        }
    }
}

private nonisolated struct FridayMemoryRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var category: FridayMemoryCategory
    var confidence: Double
    var sensitivity: FridayMemorySensitivity
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var source: FridayMemorySource
    var ttl: FridayMemoryTTL
    var reason: String

    init(
        id: UUID = UUID(),
        text: String,
        category: FridayMemoryCategory,
        confidence: Double,
        sensitivity: FridayMemorySensitivity,
        createdAt: Date,
        updatedAt: Date,
        lastUsedAt: Date? = nil,
        source: FridayMemorySource,
        ttl: FridayMemoryTTL,
        reason: String
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.confidence = confidence
        self.sensitivity = sensitivity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.source = source
        self.ttl = ttl
        self.reason = reason
    }

    init(candidate: FridayMemoryCandidate, now: Date) {
        self.init(
            text: candidate.text,
            category: candidate.category,
            confidence: candidate.confidence,
            sensitivity: candidate.sensitivity,
            createdAt: now,
            updatedAt: now,
            source: .conversation,
            ttl: candidate.ttl,
            reason: candidate.reason
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case category
        case confidence
        case sensitivity
        case createdAt
        case updatedAt
        case lastUsedAt
        case source
        case ttl
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        category = try container.decodeIfPresent(FridayMemoryCategory.self, forKey: .category) ?? .other
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.85
        sensitivity = try container.decodeIfPresent(FridayMemorySensitivity.self, forKey: .sensitivity) ?? .low
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        source = try container.decodeIfPresent(FridayMemorySource.self, forKey: .source) ?? .conversation
        ttl = try container.decodeIfPresent(FridayMemoryTTL.self, forKey: .ttl) ?? .durable
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "Migrated from earlier Friday memory."
    }

    var isExpired: Bool {
        switch ttl {
        case .durable:
            return false
        case .session:
            return true
        case .temporary:
            guard let expirationDate = Calendar.current.date(byAdding: .day, value: 14, to: updatedAt) else {
                return false
            }

            return expirationDate < Date()
        }
    }

    func matches(_ candidate: FridayMemoryCandidate) -> Bool {
        if category == candidate.category && text.normalizedFridayMemory == candidate.text.normalizedFridayMemory {
            return true
        }

        let overlap = Set(text.significantMemoryTokens).intersection(candidate.text.significantMemoryTokens)
        return category == candidate.category && overlap.count >= 2
    }

    func updated(with candidate: FridayMemoryCandidate, at date: Date) -> FridayMemoryRecord {
        var record = self
        record.text = candidate.text
        record.category = candidate.category
        record.confidence = max(confidence, candidate.confidence)
        record.sensitivity = candidate.sensitivity
        record.updatedAt = date
        record.source = .conversation
        record.ttl = candidate.ttl
        record.reason = candidate.reason
        return record
    }

    func relevanceScore(for prompt: String) -> Int {
        let promptTokens = Set(prompt.significantMemoryTokens)
        let ownTokens = Set(text.significantMemoryTokens)
        var score = promptTokens.intersection(ownTokens).count * 3

        switch category {
        case .goal, .preference, .project, .skill:
            score += 2
        case .identity, .constraint, .habit, .emotionalContext:
            score += 1
        case .relationship, .healthSensitive, .other:
            break
        }

        if promptTokens.isEmpty {
            score += category == .preference ? 1 : 0
        }

        return score
    }
}

private nonisolated struct FridayMemoryCandidate: Codable, Equatable {
    let text: String
    let category: FridayMemoryCategory
    let confidence: Double
    let sensitivity: FridayMemorySensitivity
    let ttl: FridayMemoryTTL
    let reason: String

    var shouldSave: Bool {
        let normalizedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard normalizedText.count >= 4 else { return false }
        guard ttl != .session else { return false }
        guard confidence >= 0.72 else { return false }

        if sensitivity == .high {
            return confidence >= 0.88
        }

        return ttl == .durable || confidence >= 0.85
    }
}

private nonisolated enum FridayMemoryCategory: String, Codable, CaseIterable {
    case identity
    case goal
    case preference
    case habit
    case constraint
    case relationship
    case project
    case skill
    case emotionalContext = "emotional_context"
    case healthSensitive = "health_sensitive"
    case other

    var displayName: String {
        switch self {
        case .emotionalContext:
            "emotional"
        case .healthSensitive:
            "health"
        default:
            rawValue
        }
    }
}

private nonisolated enum FridayMemorySensitivity: String, Codable {
    case low
    case medium
    case high
}

private nonisolated enum FridayMemoryTTL: String, Codable {
    case durable
    case temporary
    case session
}

private nonisolated enum FridayMemorySource: String, Codable {
    case conversation
    case inferred
}

private struct FridayMemoryClassifier {
    let settings: FridayAssistantSettings

    func candidate(
        userMessage: String,
        assistantMessage: String,
        conversation: [FridayPanelChatMessage],
        existingMemories: [FridayMemoryRecord]
    ) async -> FridayMemoryCandidate? {
        if let candidate = await openAICandidate(
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            conversation: conversation,
            existingMemories: existingMemories
        ) {
            return candidate
        }

        return fallbackCandidate(from: userMessage)
    }

    private func openAICandidate(
        userMessage: String,
        assistantMessage: String,
        conversation: [FridayPanelChatMessage],
        existingMemories: [FridayMemoryRecord]
    ) async -> FridayMemoryCandidate? {
        let apiKey = settings.apiKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return nil }

        do {
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(
                userMessage: userMessage,
                assistantMessage: assistantMessage,
                conversation: conversation,
                existingMemories: existingMemories
            ))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            let text = OpenAIClient.extractText(from: data)
            return Self.decodeCandidate(from: text)
        } catch {
            return nil
        }
    }

    private func requestBody(
        userMessage: String,
        assistantMessage: String,
        conversation: [FridayPanelChatMessage],
        existingMemories: [FridayMemoryRecord]
    ) -> [String: Any] {
        [
            "model": settings.model,
            "max_output_tokens": 350,
            "instructions": """
            You classify durable personal memory for Friday, a personal assistant.
            Return only valid JSON. Do not include markdown.
            Save only useful durable or clearly recurring facts the assistant should know later.
            Do not save one-off tasks, transient moods, secrets, API keys, passwords, raw email/PDF contents, or random facts.
            Use high sensitivity only for health or very private data.
            If nothing should be saved, return {"save":false}.
            If something should be saved, return:
            {"save":true,"text":"distilled memory","category":"identity|goal|preference|habit|constraint|relationship|project|skill|emotional_context|health_sensitive|other","confidence":0.0-1.0,"sensitivity":"low|medium|high","ttl":"durable|temporary|session","reason":"short rationale"}
            """,
            "input": """
            Existing memories:
            \(existingMemories.prefix(25).map { "- [\($0.category.rawValue)] \($0.text)" }.joined(separator: "\n"))

            Recent conversation:
            \(conversation.suffix(8).map { "\($0.role.transcriptName): \($0.text)" }.joined(separator: "\n"))

            Latest user message:
            \(userMessage)

            Assistant response:
            \(assistantMessage)
            """,
        ]
    }

    private static func decodeCandidate(from text: String) -> FridayMemoryCandidate? {
        let trimmedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard
            let data = trimmedText.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (object["save"] as? Bool) == true,
            let memoryText = object["text"] as? String
        else {
            return nil
        }

        let category = FridayMemoryCategory(rawValue: object["category"] as? String ?? "") ?? .other
        let sensitivity = FridayMemorySensitivity(rawValue: object["sensitivity"] as? String ?? "") ?? .low
        let ttl = FridayMemoryTTL(rawValue: object["ttl"] as? String ?? "") ?? .durable
        let confidence = object["confidence"] as? Double ?? 0.0
        let reason = object["reason"] as? String ?? "OpenAI classified this as useful durable memory."

        return FridayMemoryCandidate(
            text: memoryText,
            category: category,
            confidence: confidence,
            sensitivity: sensitivity,
            ttl: ttl,
            reason: reason
        )
    }

    private func fallbackCandidate(from message: String) -> FridayMemoryCandidate? {
        let lowercasedMessage = message.lowercased()
        guard let range = lowercasedMessage.range(of: "remember") else {
            return nil
        }

        let text = message[range.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " :,-"))
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard text.count >= 4 else { return nil }

        return FridayMemoryCandidate(
            text: text,
            category: .other,
            confidence: 0.95,
            sensitivity: .low,
            ttl: .durable,
            reason: "The user explicitly asked Friday to remember this."
        )
    }
}

private nonisolated struct FridayContextItem: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let source: String
    let kind: FridayContextKind
    let preview: String
    let imageDataURL: String?

    init(
        id: UUID = UUID(),
        title: String,
        source: String,
        kind: FridayContextKind,
        preview: String,
        imageDataURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.kind = kind
        self.preview = preview
        self.imageDataURL = imageDataURL
    }

    var systemName: String {
        switch kind {
        case .folder:
            "folder"
        case .pdf:
            "doc.richtext"
        case .image:
            "photo"
        case .link:
            "link"
        case .text:
            "doc.text"
        }
    }
}

private nonisolated enum FridayContextKind: String, Codable {
    case folder
    case pdf
    case image
    case link
    case text
}

private enum FridayContextPicker {
    @MainActor
    static func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func pickFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .pdf, .image, .json, .rtf, .text, .url]
        panel.prompt = "Attach"
        return panel.runModal() == .OK ? panel.urls : []
    }

    @MainActor
    static func pickOutputDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where Friday should save this generated file."
        panel.prompt = "Save Here"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private nonisolated enum FridayContextReader {
    static func items(for urls: [URL]) async -> [FridayContextItem] {
        await Task.detached(priority: .userInitiated) {
            urls.compactMap(item(for:))
        }.value
    }

    private static func item(for url: URL) -> FridayContextItem? {
        if url.hasDirectoryPath {
            return folderItem(for: url)
        }

        if url.pathExtension.lowercased() == "pdf" {
            return pdfItem(for: url)
        }

        if ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff"].contains(url.pathExtension.lowercased()) {
            return imageItem(for: url)
        }

        if url.pathExtension.lowercased() == "webloc" || url.pathExtension.lowercased() == "url" {
            return linkItem(for: url)
        }

        return textItem(for: url)
    }

    private static func folderItem(for url: URL) -> FridayContextItem? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        var snippets: [String] = []
        for case let fileURL as URL in enumerator {
            guard snippets.count < 12 else { break }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else {
                continue
            }

            if let item = item(for: fileURL), !item.preview.isEmpty {
                snippets.append("\(fileURL.lastPathComponent): \(item.preview)")
            }
        }

        return FridayContextItem(
            title: url.lastPathComponent,
            source: url.path,
            kind: .folder,
            preview: snippets.joined(separator: "\n\n").prefixString(6000)
        )
    }

    private static func pdfItem(for url: URL) -> FridayContextItem? {
        guard let document = PDFDocument(url: url) else { return nil }

        let text = (0..<min(document.pageCount, 12))
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")

        return FridayContextItem(
            title: url.lastPathComponent,
            source: url.path,
            kind: .pdf,
            preview: text.prefixString(6000)
        )
    }

    private static func imageItem(for url: URL) -> FridayContextItem? {
        let dataURL = imageDataURL(for: url)

        return FridayContextItem(
            title: url.lastPathComponent,
            source: url.path,
            kind: .image,
            preview: dataURL == nil
                ? "Image attached at \(url.path), but Friday could not prepare it for vision input."
                : "Image attached at \(url.path).",
            imageDataURL: dataURL
        )
    }

    private static func imageDataURL(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count <= 8_000_000 else {
            return nil
        }

        let mimeType: String
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            mimeType = "image/jpeg"
        case "heic":
            mimeType = "image/heic"
        case "webp":
            mimeType = "image/webp"
        case "gif":
            mimeType = "image/gif"
        case "tiff", "tif":
            mimeType = "image/tiff"
        default:
            mimeType = "image/png"
        }

        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private static func linkItem(for url: URL) -> FridayContextItem? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return FridayContextItem(
            title: url.lastPathComponent,
            source: url.path,
            kind: .link,
            preview: text.prefixString(2000)
        )
    }

    private static func textItem(for url: URL) -> FridayContextItem? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return FridayContextItem(
            title: url.lastPathComponent,
            source: url.path,
            kind: .text,
            preview: text.prefixString(6000)
        )
    }
}

private struct OpenAIClient {
    let settings: FridayAssistantSettings

    func respond(
        to message: String,
        conversation: [FridayPanelChatMessage],
        memories: [FridayMemoryRecord],
        contextItems: [FridayContextItem]
    ) async -> FridayPanelAssistantResponse? {
        let apiKey = settings.apiKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return nil }

        if Self.isVideoGenerationRequest(message) {
            return await generateVideo(message: message, contextItems: contextItems, apiKey: apiKey)
        }

        do {
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: requestBody(
                    message: message,
                    conversation: conversation,
                    memories: memories,
                    contextItems: contextItems
                )
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return FridayPanelAssistantResponse(
                    text: "OpenAI could not answer right now. Check the API key and network connection.",
                    statusText: "OpenAI error"
                )
            }

            let parsedResponse = Self.extractResponsePayload(
                from: data,
                prompt: message,
                outputDirectory: outputDirectory(from: contextItems)
            )
            return FridayPanelAssistantResponse(
                text: parsedResponse.text.isEmpty ? "I got an empty response from OpenAI." : parsedResponse.text,
                statusText: parsedResponse.mediaAttachments.isEmpty ? "OpenAI" : "Saved generated media",
                mediaAttachments: parsedResponse.mediaAttachments
            )
        } catch {
            return FridayPanelAssistantResponse(
                text: Self.message(for: error),
                statusText: "OpenAI error"
            )
        }
    }

    private static func message(for error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotFindHost:
                return "I could not reach api.openai.com. Check your internet connection, DNS/VPN, then relaunch Friday so macOS applies the network permission."
            case NSURLErrorNotConnectedToInternet:
                return "You appear to be offline. Connect to the internet and try again."
            case NSURLErrorTimedOut:
                return "OpenAI took too long to respond. Try again in a moment."
            default:
                break
            }
        }

        return "OpenAI request failed: \(error.localizedDescription)"
    }

    private func requestBody(
        message: String,
        conversation: [FridayPanelChatMessage],
        memories: [FridayMemoryRecord],
        contextItems: [FridayContextItem]
    ) -> [String: Any] {
        var content: [[String: Any]] = [
            [
                "type": "input_text",
                "text": userPrompt(
                    message: message,
                    conversation: conversation,
                    memories: memories,
                    contextItems: contextItems
                ),
            ],
        ]

        for imageURL in contextItems.compactMap(\.imageDataURL).prefix(4) {
            content.append([
                "type": "input_image",
                "image_url": imageURL,
            ])
        }

        return [
            "model": settings.model,
            "max_output_tokens": 1200,
            "tools": [
                ["type": "web_search_preview"] as [String: Any],
                ["type": "image_generation"] as [String: Any],
            ],
            "instructions": instructions,
            "input": [
                [
                    "role": "user",
                    "content": content,
                ] as [String: Any],
            ],
        ]
    }

    private var instructions: String {
        let behaviorPrompt = settings.behaviorPrompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        return """
        You are Friday, a deeply useful personal assistant. \(settings.mood.instruction)
        Be friendly and concise. Do not be verbose. Help the user actually make progress.
        Use memory and provided context when relevant. If a task is ambiguous, make a reasonable assumption and give the next concrete step.
        You can search the web when useful. Cite links briefly when web results materially affect the answer.
        You may return markdown. Use headings, bold, italics, underline HTML, horizontal rules, and markdown tables when they make the answer easier to scan.
        When the user asks for an image, use the image generation tool. When the user asks for video, keep the response short because Friday handles video generation separately.
        Never invent that you read a file, image, PDF, email, or website unless context or tool results include it.
        \(behaviorPrompt.isEmpty ? "" : "\nUser custom behavior instructions:\n\(behaviorPrompt)")
        """
    }

    private func userPrompt(
        message: String,
        conversation: [FridayPanelChatMessage],
        memories: [FridayMemoryRecord],
        contextItems: [FridayContextItem]
    ) -> String {
        let transcript = conversation.suffix(12)
            .map { "\($0.role.transcriptName): \($0.text)" }
            .joined(separator: "\n")
        let memory = memories
            .map { "- [\($0.category.rawValue)] \($0.text)" }
            .joined(separator: "\n")
        let context = contextItems.prefix(10)
            .map { "- \($0.title) [\($0.kind.rawValue)]: \($0.preview)" }
            .joined(separator: "\n\n")

        return """
        Current date: \(Date().formatted(date: .abbreviated, time: .shortened))
        Mood: \(settings.mood.rawValue)
        Custom behavior instructions:
        \(settings.behaviorPrompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))

        Relevant saved memory:
        \(memory)

        User-selected local context:
        \(context)

        Recent conversation:
        \(transcript)

        User asks:
        \(message)
        """
    }

    static func extractText(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
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

    private func generateVideo(
        message: String,
        contextItems: [FridayContextItem],
        apiKey: String
    ) async -> FridayPanelAssistantResponse {
        do {
            var createRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/videos")!)
            createRequest.httpMethod = "POST"
            createRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            createRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": "sora-2",
                "prompt": message,
                "seconds": 4,
                "size": "720x1280",
            ] as [String: Any])

            let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
            guard
                let httpCreateResponse = createResponse as? HTTPURLResponse,
                (200..<300).contains(httpCreateResponse.statusCode),
                let createObject = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
                let videoID = createObject["id"] as? String
            else {
                return FridayPanelAssistantResponse(
                    text: "I could not start video generation right now. Check the API key and whether your OpenAI account has video generation enabled.",
                    statusText: "Video error"
                )
            }

            let completedID = try await pollVideo(id: videoID, apiKey: apiKey)
            let data = try await downloadVideo(id: completedID, apiKey: apiKey)
            let url = try Self.saveGeneratedMedia(
                data: data,
                kind: .video,
                prompt: message,
                outputDirectory: outputDirectory(from: contextItems)
            )

            let directoryText = outputDirectory(from: contextItems) == nil
                ? "I generated the video. Use the download button to choose a final folder."
                : "I generated the video and saved it in your selected context folder."

            return FridayPanelAssistantResponse(
                text: directoryText,
                statusText: "Saved video",
                mediaAttachments: [
                    FridayGeneratedMediaAttachment(kind: .video, url: url, prompt: message),
                ]
            )
        } catch {
            return FridayPanelAssistantResponse(
                text: "Video generation failed: \(error.localizedDescription)",
                statusText: "Video error"
            )
        }
    }

    private func pollVideo(id: String, apiKey: String) async throws -> String {
        for _ in 0..<60 {
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/videos/\(id)")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                throw FridayOpenAIError.videoPollingFailed
            }

            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FridayOpenAIError.videoPollingFailed
            }

            let status = object["status"] as? String ?? ""
            if status == "completed" || status == "succeeded" {
                return id
            }

            if status == "failed" || status == "cancelled" {
                throw FridayOpenAIError.videoGenerationFailed
            }

            try await Task.sleep(for: .seconds(4))
        }

        throw FridayOpenAIError.videoTimedOut
    }

    private func downloadVideo(id: String, apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/videos/\(id)/content")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw FridayOpenAIError.videoDownloadFailed
        }

        return data
    }

    private func outputDirectory(from contextItems: [FridayContextItem]) -> URL? {
        contextItems.first(where: { $0.kind == .folder }).map {
            URL(fileURLWithPath: $0.source, isDirectory: true)
        }
    }

    private static func isVideoGenerationRequest(_ message: String) -> Bool {
        let tokens = Set(message.significantMemoryTokens)
        let asksForGeneration = !tokens.intersection(["generate", "create", "make", "render", "produce"]).isEmpty
        let asksForVideo = !tokens.intersection(["video", "movie", "clip", "animation"]).isEmpty
        return asksForGeneration && asksForVideo
    }

    private static func extractResponsePayload(
        from data: Data,
        prompt: String,
        outputDirectory: URL?
    ) -> FridayOpenAIResponsePayload {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FridayOpenAIResponsePayload(text: "", mediaAttachments: [])
        }

        let text = extractText(from: data)
        var attachments: [FridayGeneratedMediaAttachment] = []

        if let output = object["output"] as? [[String: Any]] {
            for item in output {
                if let base64 = imageBase64(from: item), let imageData = Data(base64Encoded: base64) {
                    do {
                        let url = try saveGeneratedMedia(
                            data: imageData,
                            kind: .image,
                            prompt: prompt,
                            outputDirectory: outputDirectory
                        )
                        attachments.append(FridayGeneratedMediaAttachment(kind: .image, url: url, prompt: prompt))
                    } catch {
                        NSLog("Friday failed to save generated image: \(error.localizedDescription)")
                    }
                }
            }
        }

        return FridayOpenAIResponsePayload(text: text, mediaAttachments: attachments)
    }

    private static func imageBase64(from item: [String: Any]) -> String? {
        if let result = item["result"] as? String {
            return result
        }

        if let image = item["image"] as? String {
            return image
        }

        guard let content = item["content"] as? [[String: Any]] else {
            return nil
        }

        return content.compactMap { contentItem in
            contentItem["result"] as? String
                ?? contentItem["image"] as? String
                ?? contentItem["b64_json"] as? String
        }.first
    }

    private static func saveGeneratedMedia(
        data: Data,
        kind: FridayGeneratedMediaKind,
        prompt: String,
        outputDirectory: URL?
    ) throws -> URL {
        let directory: URL
        if let outputDirectory {
            directory = outputDirectory
        } else {
            directory = try generatedMediaDirectory()
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970)
        let baseName = "friday-\(kind.fileExtension)-\(timestamp).\(kind.fileExtension)"
        let destination = uniqueURL(in: directory, preferredName: baseName)
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    private static func generatedMediaDirectory() throws -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Friday", directoryHint: .isDirectory)
            .appending(path: "Generated Media", directoryHint: .isDirectory)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Friday Generated Media", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    private static func uniqueURL(in directory: URL, preferredName: String) -> URL {
        let baseURL = directory.appending(path: preferredName, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let extensionValue = baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent
        for index in 2..<1000 {
            let candidate = directory.appending(path: "\(stem)-\(index).\(extensionValue)", directoryHint: .notDirectory)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appending(path: "\(stem)-\(UUID().uuidString).\(extensionValue)", directoryHint: .notDirectory)
    }
}

private nonisolated struct FridayOpenAIResponsePayload: Equatable {
    let text: String
    let mediaAttachments: [FridayGeneratedMediaAttachment]
}

private nonisolated enum FridayOpenAIError: LocalizedError {
    case videoPollingFailed
    case videoGenerationFailed
    case videoTimedOut
    case videoDownloadFailed

    var errorDescription: String? {
        switch self {
        case .videoPollingFailed:
            "Friday could not check the video generation status."
        case .videoGenerationFailed:
            "OpenAI reported that the video generation failed."
        case .videoTimedOut:
            "OpenAI is still generating the video. Try again with a shorter prompt."
        case .videoDownloadFailed:
            "Friday could not download the generated video."
        }
    }
}

private extension JSONDecoder {
    static var fridayAssistant: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var fridayAssistant: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private nonisolated extension String {
    var normalizedFridayMemory: String {
        lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var significantMemoryTokens: [String] {
        components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { $0.count >= 3 }
    }

    func prefixString(_ count: Int) -> String {
        String(prefix(count))
    }

    var cleanedRSSString: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var strippingMarkdownCodeFence: String {
        let trimmed = trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return trimmed }

        return lines
            .dropFirst()
            .dropLast()
            .joined(separator: "\n")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

@MainActor
private final class HomePanelDataProvider: ObservableObject {
    @Published private(set) var calendarSummary = HomeCalendarSummary.loading
    @Published private(set) var mailSummary = HomeMailSummary.loading

    private let calendarService: HomeCalendarReading = HomeEventKitCalendarReader()
    private let mailService: HomeMailReading = HomeMailAppleScriptReader()

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

    private func refreshCalendar() async {
        do {
            calendarSummary = try await calendarService.todaySummary()
        } catch {
            calendarSummary = .unavailable(error.localizedDescription)
        }
    }

    private func refreshMail() async {
        do {
            mailSummary = try await mailService.inboxSummary()
        } catch {
            mailSummary = .unavailable(error.localizedDescription)
        }
    }
}

private struct HomeCalendarSummary: Equatable {
    let eventCount: Int
    let nextEventTitle: String?
    let statusMessage: String?

    static let loading = HomeCalendarSummary(
        eventCount: 0,
        nextEventTitle: nil,
        statusMessage: "Checking calendar access"
    )

    static func unavailable(_ message: String) -> HomeCalendarSummary {
        HomeCalendarSummary(eventCount: 0, nextEventTitle: nil, statusMessage: message)
    }
}

private struct HomeMailSummary: Equatable {
    let unreadCount: Int
    let latestSubject: String?
    let statusMessage: String?

    static let loading = HomeMailSummary(
        unreadCount: 0,
        latestSubject: nil,
        statusMessage: "Checking Mail access"
    )

    static func unavailable(_ message: String) -> HomeMailSummary {
        HomeMailSummary(unreadCount: 0, latestSubject: nil, statusMessage: message)
    }
}

private protocol HomeCalendarReading {
    func todaySummary() async throws -> HomeCalendarSummary
}

private protocol HomeMailReading {
    func inboxSummary() async throws -> HomeMailSummary
}

private final class HomeEventKitCalendarReader: HomeCalendarReading {
    private let eventStore = EKEventStore()

    func todaySummary() async throws -> HomeCalendarSummary {
        try await requestCalendarAccessIfNeeded()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw HomePanelDataError.invalidDateRange
        }

        let predicate = eventStore.predicateForEvents(
            withStart: Date(),
            end: endOfDay,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        return HomeCalendarSummary(
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
            guard isGranted else { throw HomePanelDataError.calendarAccessDenied }
        case .denied, .restricted, .writeOnly:
            throw HomePanelDataError.calendarAccessDenied
        @unknown default:
            throw HomePanelDataError.calendarAccessDenied
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

private final class HomeMailAppleScriptReader: HomeMailReading {
    private nonisolated static let mailBundleIdentifier = "com.apple.mail"

    func inboxSummary() async throws -> HomeMailSummary {
        let result = try await Task.detached(priority: .userInitiated) {
            try Self.executeInboxScript()
        }.value

        return HomeMailSummary(
            unreadCount: result.unreadCount,
            latestSubject: result.latestSubject,
            statusMessage: nil
        )
    }

    private nonisolated static func executeInboxScript() throws -> (unreadCount: Int, latestSubject: String?) {
        guard isMailRunning else {
            throw HomePanelDataError.mailNotRunning
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
            throw HomePanelDataError.mailScriptUnavailable
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            throw HomePanelDataError.mailAutomationFailed(message(from: errorInfo))
        }

        let output = descriptor.stringValue ?? ""
        let parts = output.components(separatedBy: .newlines)
        let unreadCount = Int(parts.first ?? "") ?? 0
        let latestSubject = parts.dropFirst().first.flatMap { $0.isEmpty ? nil : $0 }

        return (unreadCount, latestSubject)
    }

    private nonisolated static func message(from errorInfo: NSDictionary) -> String {
        guard let message = errorInfo[NSAppleScript.errorMessage] as? String else {
            return "Mail automation was not allowed"
        }

        if message == "Application isn’t running." || message == "Application isn't running." {
            return "Mail is open, but macOS has not made it available to Friday yet"
        }

        return message
    }

    private nonisolated static var isMailRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == mailBundleIdentifier
        }
    }
}

private enum HomePanelDataError: LocalizedError {
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

private struct SidebarView: View {
    @Binding var selection: SidebarItem

    private let items = SidebarItem.defaults

    var body: some View {
        VStack(spacing: Layout.sidebarItemSpacing) {
            ForEach(items) { item in
                SidebarButton(
                    item: item,
                    isSelected: item == selection
                ) {
                    selection = item
                }
            }
        }
        .padding(.vertical, Layout.sidebarVerticalPadding)
        .padding(.horizontal, Layout.sidebarHorizontalPadding)
        .glassSurface(cornerRadius: Layout.sidebarCornerRadius)
    }
}

private struct SettingsPanel: View {
    @ObservedObject var store: FridayAssistantStore

    @State private var isClearMemoryHovered = false
    @State private var isClearContextHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.panelSpacing) {
            settingsHeader

            ScrollView {
                VStack(alignment: .leading, spacing: Layout.panelSpacing) {
                    apiKeySection
                    moodSection
                    behaviorPromptSection
                    summarySection
                    memoryList
                    actionButtons
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(Layout.panelPadding)
        .frame(width: Layout.panelWidth, height: Layout.panelHeight)
        .glassSurface(cornerRadius: Layout.panelCornerRadius)
    }

    private var settingsHeader: some View {
        HStack(spacing: Layout.headerSpacing) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.white)
                .frame(width: Layout.appIconSize, height: Layout.appIconSize)
                .background(AppColor.black.opacity(0.2), in: Circle())

            Text("Settings")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OpenAI API Key")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            SecureField("sk-...", text: $store.settings.apiKey)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(AppColor.black.opacity(0.24), in: .rect(cornerRadius: 12, style: .continuous))

            Text("Stored securely in macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mood")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            Picker("", selection: $store.settings.mood) {
                ForEach(FridayAssistantMood.allCases) { mood in
                    Text(mood.rawValue).tag(mood)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)
        }
    }

    private var behaviorPromptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System Prompt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            TextEditor(text: $store.settings.behaviorPrompt)
                .font(.callout)
                .foregroundStyle(.white)
                .tint(.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 92, maxHeight: 128)
                .padding(10)
                .background(AppColor.black.opacity(0.24), in: .rect(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if store.settings.behaviorPrompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                        Text("Tell Friday how to behave. Example: be direct, challenge weak assumptions, and keep answers under five sentences unless I ask for depth.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.36))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            Text("Applied to every Friday response and stored locally with app settings.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var summarySection: some View {
        VStack(spacing: Layout.rowSpacing) {
            SettingsStatRow(
                systemName: "brain.head.profile",
                title: "Memory",
                subtitle: "\(store.memories.count) saved memor\(store.memories.count == 1 ? "y" : "ies")"
            )

            SettingsStatRow(
                systemName: "folder",
                title: "Context",
                subtitle: "\(store.contextItems.count) attached item\(store.contextItems.count == 1 ? "" : "s")"
            )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button("Clear memory", action: store.clearMemory)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(AppColor.black.opacity(isClearMemoryHovered ? 0.34 : 0.22), in: .rect(cornerRadius: 10, style: .continuous))
                .cursor(.pointingHand)
                .onHover { isClearMemoryHovered = $0 }

            Button("Clear context", action: store.clearContext)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(AppColor.black.opacity(isClearContextHovered ? 0.34 : 0.22), in: .rect(cornerRadius: 10, style: .continuous))
                .cursor(.pointingHand)
                .onHover { isClearContextHovered = $0 }
        }
    }

    private var memoryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved Memory")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            if store.memories.isEmpty {
                Text("Friday will save useful details as you talk.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AppColor.black.opacity(0.18), in: .rect(cornerRadius: 10, style: .continuous))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.memories) { memory in
                            MemorySettingsRow(memory: memory) {
                                store.deleteMemory(id: memory.id)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(minHeight: 100, maxHeight: 180)
            }
        }
    }
}

private struct MemorySettingsRow: View {
    let memory: FridayMemoryRecord
    let delete: () -> Void

    @State private var isDeleteHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(memory.category.displayName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.76))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(AppColor.black.opacity(0.22), in: .rect(cornerRadius: 7, style: .continuous))

            Text(memory.text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(2)

            Spacer(minLength: 0)

            Button(action: delete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .background(AppColor.black.opacity(isDeleteHovered ? 0.34 : 0.18), in: Circle())
            .cursor(.pointingHand)
            .onHover { isDeleteHovered = $0 }
        }
        .padding(8)
        .background(AppColor.black.opacity(0.18), in: .rect(cornerRadius: 10, style: .continuous))
    }
}

private struct SettingsStatRow: View {
    let systemName: String
    let title: String
    let subtitle: String

    var body: some View {
        ContentRow(item: .init(systemName: systemName, title: title, subtitle: subtitle))
    }
}

private struct StockMarketPanel: View {
    @StateObject private var viewModel = StockMarketViewModel()
    @State private var tickerText = "AAPL"
    @State private var isRefreshHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            rangeSelector

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    priceHeader
                    StockChartView(points: viewModel.points, isPositive: viewModel.quote?.isPositive ?? true)
                        .frame(height: 190)
                    statsGrid
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                StockNewsCard(item: viewModel.news.first, ticker: viewModel.symbol)
                    .frame(width: 250)
            }

            if let message = viewModel.statusMessage {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(Layout.panelPadding)
        .frame(width: Layout.panelWidth, height: Layout.panelHeight)
        .glassSurface(cornerRadius: Layout.panelCornerRadius)
        .task {
            await viewModel.load(symbol: tickerText)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.white)
                .frame(width: Layout.appIconSize, height: Layout.appIconSize)
                .background(AppColor.black.opacity(0.2), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("Markets")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Live quote, chart, and market context")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.54))
            }

            Spacer()

            TextField("AAPL", text: $tickerText)
                .textFieldStyle(.plain)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .tint(.white)
                .multilineTextAlignment(.center)
                .textCase(.uppercase)
                .frame(width: 76, height: 32)
                .background(AppColor.black.opacity(0.24), in: .rect(cornerRadius: 10, style: .continuous))
                .onSubmit {
                    Task { await viewModel.load(symbol: tickerText) }
                }

            Button {
                Task { await viewModel.load(symbol: tickerText) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.white)
            }
            .buttonStyle(.plain)
            .frame(width: Layout.headerButtonSize, height: Layout.headerButtonSize)
            .background(AppColor.black.opacity(isRefreshHovered ? 0.32 : 0.2), in: Circle())
            .cursor(.pointingHand)
            .onHover { isRefreshHovered = $0 }
            .help("Refresh")
        }
    }

    private var priceHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(viewModel.quote?.shortName ?? viewModel.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(viewModel.quote?.priceText ?? "--")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(viewModel.quote?.changeText ?? "")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(viewModel.quote?.isPositive == false ? Color(red: 1, green: 0.42, blue: 0.42) : Color(red: 0.48, green: 1, blue: 0.62))
            }
        }
    }

    private var rangeSelector: some View {
        HStack(spacing: 8) {
            ForEach(StockChartRange.allCases) { range in
                Button {
                    Task { await viewModel.setRange(range) }
                } label: {
                    Text(range.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(viewModel.range == range ? 0.98 : 0.58))
                        .frame(width: 42, height: 26)
                        .background(AppColor.black.opacity(viewModel.range == range ? 0.34 : 0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }

            Spacer()
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: Layout.contextGridColumns, spacing: 10) {
            StockStatCell(title: "Open", value: viewModel.quote?.openText ?? "--")
            StockStatCell(title: "High", value: viewModel.quote?.highText ?? "--")
            StockStatCell(title: "Low", value: viewModel.quote?.lowText ?? "--")
            StockStatCell(title: "Volume", value: viewModel.quote?.volumeText ?? "--")
        }
    }
}

private struct StockChartView: View {
    let points: [Double]
    let isPositive: Bool

    var body: some View {
        Canvas { context, size in
            guard points.count > 1, let minValue = points.min(), let maxValue = points.max() else {
                return
            }

            let spread = max(maxValue - minValue, 0.001)
            let stepX = size.width / CGFloat(points.count - 1)

            var path = Path()
            for (index, point) in points.enumerated() {
                let x = CGFloat(index) * stepX
                let y = size.height - CGFloat((point - minValue) / spread) * size.height
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()

            let color = isPositive
                ? Color(red: 0.56, green: 0.76, blue: 1)
                : Color(red: 1, green: 0.48, blue: 0.56)

            context.fill(fillPath, with: .linearGradient(
                Gradient(colors: [color.opacity(0.22), color.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            context.stroke(path, with: .color(color.opacity(0.95)), lineWidth: 2)
        }
        .background(AppColor.black.opacity(0.12), in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColor.white.opacity(0.1), lineWidth: 1)
        }
    }
}

private struct StockStatCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.48))

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColor.black.opacity(0.18), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

private struct StockNewsCard: View {
    let item: StockNewsItem?
    let ticker: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Analysis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.54))

                Spacer()

                Image(systemName: "newspaper")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.54))
            }

            Text(item?.title ?? "\(ticker) market context")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.black.opacity(0.92))
                .lineLimit(4)

            Text(item?.summary ?? "Friday will show recent market context here when news is available for this ticker.")
                .font(.caption)
                .foregroundStyle(.black.opacity(0.62))
                .lineSpacing(2)
                .lineLimit(9)

            Spacer(minLength: 0)

            HStack {
                Circle()
                    .fill(.black.opacity(0.34))
                    .frame(width: 5, height: 5)

                Text(item?.source ?? "Market feed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.48))

                Spacer()
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 24, style: .continuous))
        .background(AppColor.white.opacity(0.62), in: .rect(cornerRadius: 24, style: .continuous))
        .foregroundStyle(AppColor.black)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppColor.white.opacity(0.38), lineWidth: 1)
        }
    }
}

@MainActor
private final class StockMarketViewModel: ObservableObject {
    @Published private(set) var symbol = "AAPL"
    @Published private(set) var range = StockChartRange.oneMonth
    @Published private(set) var quote: StockQuote?
    @Published private(set) var points: [Double] = []
    @Published private(set) var news: [StockNewsItem] = []
    @Published private(set) var statusMessage: String?

    private let service = StockMarketService()

    func load(symbol rawSymbol: String) async {
        let cleanedSymbol = rawSymbol
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .uppercased()
        guard !cleanedSymbol.isEmpty else { return }

        symbol = cleanedSymbol
        statusMessage = "Loading \(cleanedSymbol)"

        do {
            async let chartResponse = service.chart(symbol: cleanedSymbol, range: range)
            async let newsResponse = service.news(symbol: cleanedSymbol)

            let chart = try await chartResponse
            quote = chart.quote
            points = chart.points
            news = await (try? newsResponse) ?? []
            statusMessage = "Market data from Yahoo Finance. Delayed where exchanges require it."
        } catch {
            quote = nil
            points = []
            news = []
            statusMessage = "Could not load \(cleanedSymbol): \(error.localizedDescription)"
        }
    }

    func setRange(_ range: StockChartRange) async {
        self.range = range
        await load(symbol: symbol)
    }
}

private struct StockQuote: Equatable {
    let symbol: String
    let shortName: String
    let price: Double
    let previousClose: Double?
    let open: Double?
    let high: Double?
    let low: Double?
    let volume: Double?
    let currency: String

    var change: Double? {
        guard let previousClose else { return nil }
        return price - previousClose
    }

    var changePercent: Double? {
        guard let previousClose, previousClose != 0 else { return nil }
        return ((price - previousClose) / previousClose) * 100
    }

    var isPositive: Bool {
        (change ?? 0) >= 0
    }

    var priceText: String {
        price.formatted(.number.precision(.fractionLength(2)))
    }

    var changeText: String {
        guard let change, let changePercent else { return "" }
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(change.formatted(.number.precision(.fractionLength(2)))) (\(sign)\(changePercent.formatted(.number.precision(.fractionLength(2))))%)"
    }

    var openText: String { formatted(open) }
    var highText: String { formatted(high) }
    var lowText: String { formatted(low) }

    var volumeText: String {
        guard let volume else { return "--" }
        return volume.formatted(.number.notation(.compactName).precision(.fractionLength(1)))
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.precision(.fractionLength(2)))
    }
}

private struct StockChartResponse: Equatable {
    let quote: StockQuote
    let points: [Double]
}

private struct StockNewsItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let summary: String
    let source: String
}

private enum StockChartRange: String, CaseIterable, Identifiable {
    case oneDay
    case oneWeek
    case oneMonth
    case threeMonths
    case oneYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay: "1D"
        case .oneWeek: "1W"
        case .oneMonth: "1M"
        case .threeMonths: "3M"
        case .oneYear: "1Y"
        }
    }

    var yahooRange: String {
        switch self {
        case .oneDay: "1d"
        case .oneWeek: "5d"
        case .oneMonth: "1mo"
        case .threeMonths: "3mo"
        case .oneYear: "1y"
        }
    }

    var yahooInterval: String {
        switch self {
        case .oneDay: "5m"
        case .oneWeek: "30m"
        case .oneMonth: "1d"
        case .threeMonths: "1d"
        case .oneYear: "1wk"
        }
    }
}

private struct StockMarketService {
    func chart(symbol: String, range: StockChartRange) async throws -> StockChartResponse {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)")!
        components.queryItems = [
            URLQueryItem(name: "range", value: range.yahooRange),
            URLQueryItem(name: "interval", value: range.yahooInterval),
            URLQueryItem(name: "includePrePost", value: "false"),
        ]

        guard let url = components.url else {
            throw StockMarketError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw StockMarketError.requestFailed
        }

        return try Self.parseChart(data: data, fallbackSymbol: symbol)
    }

    func news(symbol: String) async throws -> [StockNewsItem] {
        var components = URLComponents(string: "https://feeds.finance.yahoo.com/rss/2.0/headline")!
        components.queryItems = [
            URLQueryItem(name: "s", value: symbol),
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "lang", value: "en-US"),
        ]

        guard let url = components.url else {
            throw StockMarketError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw StockMarketError.requestFailed
        }

        return StockNewsRSSParser.items(from: data)
    }

    private static func parseChart(data: Data, fallbackSymbol: String) throws -> StockChartResponse {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let chart = object["chart"] as? [String: Any],
            let result = (chart["result"] as? [[String: Any]])?.first,
            let meta = result["meta"] as? [String: Any]
        else {
            throw StockMarketError.invalidResponse
        }

        let indicators = result["indicators"] as? [String: Any]
        let quoteObject = (indicators?["quote"] as? [[String: Any]])?.first
        let closes = (quoteObject?["close"] as? [Any])?
            .compactMap { $0 as? Double }
            ?? []

        let price = meta["regularMarketPrice"] as? Double
            ?? closes.last
            ?? 0

        let quote = StockQuote(
            symbol: meta["symbol"] as? String ?? fallbackSymbol,
            shortName: meta["shortName"] as? String ?? meta["symbol"] as? String ?? fallbackSymbol,
            price: price,
            previousClose: meta["chartPreviousClose"] as? Double ?? meta["previousClose"] as? Double,
            open: meta["regularMarketOpen"] as? Double,
            high: meta["regularMarketDayHigh"] as? Double,
            low: meta["regularMarketDayLow"] as? Double,
            volume: meta["regularMarketVolume"] as? Double,
            currency: meta["currency"] as? String ?? "USD"
        )

        return StockChartResponse(quote: quote, points: closes)
    }
}

private final class StockNewsRSSParser: NSObject, XMLParserDelegate {
    private var items: [StockNewsItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var isInsideItem = false

    static func items(from data: Data) -> [StockNewsItem] {
        let parserDelegate = StockNewsRSSParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        parser.parse()
        return parserDelegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            isInsideItem = true
            currentTitle = ""
            currentDescription = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }

        switch currentElement {
        case "title":
            currentTitle += string
        case "description":
            currentDescription += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            let title = currentTitle.cleanedRSSString
            let summary = currentDescription.cleanedRSSString
            if !title.isEmpty {
                items.append(StockNewsItem(title: title, summary: summary, source: "Yahoo Finance"))
            }
            isInsideItem = false
        }
        currentElement = ""
    }
}

private enum StockMarketError: LocalizedError {
    case invalidURL
    case requestFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid market data URL"
        case .requestFailed:
            "Market data request failed"
        case .invalidResponse:
            "Market data response was not readable"
        }
    }
}

private struct StubPanel: View {
    let systemName: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.panelSpacing) {
            HStack(spacing: Layout.headerSpacing) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.white)
                    .frame(width: Layout.appIconSize, height: Layout.appIconSize)
                    .background(AppColor.black.opacity(0.2), in: Circle())

                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()
            }

            Text(subtitle)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                StubRow(systemName: "sparkle.magnifyingglass", title: "Overview", subtitle: "Connect real data and actions here.")
                StubRow(systemName: "rectangle.stack", title: "Recent", subtitle: "Recent items will appear in this section.")
                StubRow(systemName: "slider.horizontal.3", title: "Controls", subtitle: "Filters and controls will be added as the feature grows.")
            }

            Spacer()
        }
        .padding(Layout.panelPadding)
        .frame(width: Layout.panelWidth, height: Layout.panelHeight)
        .glassSurface(cornerRadius: Layout.panelCornerRadius)
    }
}

private struct StubRow: View {
    let systemName: String
    let title: String
    let subtitle: String

    var body: some View {
        ContentRow(item: .init(systemName: systemName, title: title, subtitle: subtitle))
    }
}

private struct SearchOverlay: View {
    @Binding var isPresented: Bool

    @FocusState private var isSearchFocused: Bool
    @State private var isClearButtonHovered = false
    @State private var isCommandFieldHovered = false
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private var displayedQuery: String {
        trimmedQuery.isEmpty ? "Untitled" : trimmedQuery
    }

    var body: some View {
        VStack(spacing: Layout.searchPanelSpacing) {
            commandField

            VStack(spacing: 0) {
                searchHeader

                Divider()
                    .background(.white.opacity(0.14))

                emptyState

                Divider()
                    .background(.white.opacity(0.14))

                searchFooter
            }
            .frame(width: Layout.searchPanelWidth)
            .glassSurface(cornerRadius: Layout.searchCornerRadius)
        }
        .onAppear {
            isSearchFocused = true
        }
        .onExitCommand(perform: dismiss)
    }

    private var commandField: some View {
        HStack(spacing: Layout.searchFieldSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColor.orange.opacity(0.95))

            TextField("Type a command or search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .tint(AppColor.orange)
                .focused($isSearchFocused)

            Spacer(minLength: Layout.searchFieldSpacing)

            KeyboardShortcutPill(text: "⌘/")
        }
        .padding(.horizontal, Layout.searchFieldHorizontalPadding)
        .frame(width: Layout.searchPanelWidth, height: Layout.searchFieldHeight)
        .glassSurface(cornerRadius: Layout.searchCornerRadius)
        .overlay {
            RoundedRectangle(cornerRadius: Layout.searchCornerRadius, style: .continuous)
                .stroke(AppColor.orange.opacity(isCommandFieldHovered ? 0.52 : 0), lineWidth: 1)
        }
        .brightness(isCommandFieldHovered ? 0.04 : 0)
        .cursor(.iBeam)
        .onHover { isCommandFieldHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isCommandFieldHovered)
        .onTapGesture {
            isSearchFocused = true
        }
    }

    private var searchHeader: some View {
        HStack(spacing: Layout.searchFieldSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColor.orange.opacity(0.95))

            Image(systemName: "number")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.white.opacity(0.92))
                .frame(width: Layout.searchTokenSize, height: Layout.searchTokenSize)
                .background(AppColor.orange.opacity(0.28), in: .rect(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppColor.orange.opacity(0.34), lineWidth: 1)
                }

            Text(displayedQuery)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            KeyboardShortcutPill(text: "⌘/")
        }
        .padding(.horizontal, Layout.searchFieldHorizontalPadding)
        .frame(height: Layout.searchHeaderHeight)
    }

    private var emptyState: some View {
        VStack(spacing: Layout.searchEmptyStateSpacing) {
            Image(systemName: "number")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AppColor.orange.opacity(0.96))
                .frame(width: Layout.searchEmptyIconSize, height: Layout.searchEmptyIconSize)
                .background(AppColor.orange.opacity(0.16), in: .rect(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColor.orange.opacity(0.32), lineWidth: 1)
                }

            Text("No tags found")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Text("\"\(displayedQuery)\" did not match any tags currently used in projects.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: Layout.searchEmptyTextWidth)

            Button("Clear search", action: clearSearch)
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: Layout.searchClearButtonHeight)
                .liquidGlassButton(isHovered: isClearButtonHovered, cornerRadius: 10)
                .scaleEffect(isClearButtonHovered ? 1.03 : 1)
                .cursor(.pointingHand)
                .onHover { isClearButtonHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isClearButtonHovered)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.searchEmptyStateHeight)
        .background {
            SearchRings()
                .opacity(0.34)
        }
    }

    private var searchFooter: some View {
        HStack(spacing: Layout.searchFooterSpacing) {
            SearchFooterItem(symbol: "#", title: "tags")
            SearchFooterItem(systemName: "arrow.up", title: "navigate")
            SearchFooterItem(systemName: "arrow.down", title: "")
            SearchFooterItem(systemName: "return", title: "open")
            SearchFooterItem(text: "esc", title: "close")
            SearchFooterItem(systemName: "arrow.left", title: "parent")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.searchFooterHorizontalPadding)
        .frame(height: Layout.searchFooterHeight)
        .background(AppColor.black.opacity(0.18))
    }

    private func clearSearch() {
        query = ""
        isSearchFocused = true
    }

    private func dismiss() {
        isPresented = false
    }
}

private struct KeyboardShortcutPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(AppColor.white.opacity(0.82))
            .frame(width: Layout.keyboardShortcutWidth, height: Layout.keyboardShortcutHeight)
            .background(AppColor.black.opacity(0.24), in: .rect(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppColor.orange.opacity(0.22), lineWidth: 1)
            }
    }
}

private struct SearchFooterItem: View {
    let symbol: String?
    let systemName: String?
    let text: String?
    let title: String

    init(symbol: String, title: String) {
        self.symbol = symbol
        self.systemName = nil
        self.text = nil
        self.title = title
    }

    init(systemName: String, title: String) {
        self.symbol = nil
        self.systemName = systemName
        self.text = nil
        self.title = title
    }

    init(text: String, title: String) {
        self.symbol = nil
        self.systemName = nil
        self.text = text
        self.title = title
    }

    var body: some View {
        HStack(spacing: 8) {
            keyCap

            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    @ViewBuilder
    private var keyCap: some View {
        ZStack {
            if let symbol {
                Text(symbol)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
            } else if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
            } else if let text {
                Text(text)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white.opacity(0.84))
        .frame(width: Layout.searchFooterKeySize, height: Layout.searchFooterKeySize)
        .background(AppColor.orange.opacity(0.18), in: .rect(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColor.orange.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct SearchRings: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: 40)
            let stroke = StrokeStyle(lineWidth: 1)

            for radius in stride(from: CGFloat(48), through: CGFloat(220), by: 42) {
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )

                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(AppColor.orange.opacity(0.16)),
                    style: stroke
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SidebarButton: View {
    @State private var isHovered = false

    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: item.systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(foregroundStyle)
                .frame(width: Layout.sidebarButtonSize, height: Layout.sidebarButtonSize)
                .background(selectedBackground, in: Circle())
                .scaleEffect(isHovered ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .cursor(.pointingHand)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(item.title)
        .accessibilityLabel(item.title)
    }

    private var foregroundStyle: Color {
        if isSelected || isHovered {
            return AppColor.white
        }

        return AppColor.white.opacity(0.72)
    }

    private var selectedBackground: Color {
        if isSelected {
            return AppColor.black.opacity(isHovered ? 0.52 : 0.42)
        }

        return isHovered ? AppColor.orange.opacity(0.22) : .clear
    }
}

private struct ContextItem: Identifiable {
    let systemName: String
    let title: String
    let subtitle: String

    var id: String { title }
}

private struct ContextCard: View {
    let item: ContextItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.orange.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(AppColor.orange.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(height: Layout.contextCardHeight)
        .background(
            AppColor.black.opacity(0.2),
            in: .rect(cornerRadius: Layout.contentRowCornerRadius, style: .continuous)
        )
    }
}

private struct PromptField: View {
    @State private var isHovered = false

    @Binding var text: String
    let placeholder: String
    let isFocused: FocusState<Bool>.Binding
    let namespace: Namespace.ID
    let matchedGeometryID: String
    let onSubmit: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))
                    .allowsHitTesting(false)
            }

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.white)
                .tint(.white)
                .focused(isFocused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, Layout.promptHorizontalPadding)
        .frame(height: Layout.promptHeight)
        .background(
            AppColor.black.opacity(isHovered ? 0.36 : 0.26),
            in: .rect(cornerRadius: Layout.promptCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Layout.promptCornerRadius, style: .continuous)
                .stroke(AppColor.orange.opacity(isHovered ? 0.34 : 0), lineWidth: 1)
        }
        .cursor(.iBeam)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .matchedGeometryEffect(id: matchedGeometryID, in: namespace)
    }
}

private struct PanelItem: Identifiable {
    let systemName: String
    let title: String
    let subtitle: String

    var id: String { title }
}

private struct ContentRow: View {
    let item: PanelItem

    var body: some View {
        HStack(spacing: Layout.contentRowSpacing) {
            Image(systemName: item.systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColor.orange.opacity(0.9))
                .frame(width: Layout.contentIconSize, height: Layout.contentIconSize)
                .background(AppColor.orange.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: Layout.contentTextSpacing) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer()
        }
        .padding(Layout.contentRowPadding)
        .background(
            AppColor.black.opacity(0.22),
            in: .rect(cornerRadius: Layout.contentRowCornerRadius, style: .continuous)
        )
    }
}

private extension SidebarItem {
    static let home = SidebarItem(systemName: "house", title: "Home")
    static let search = SidebarItem(systemName: "magnifyingglass", title: "Search")
    static let mail = SidebarItem(systemName: "mail.stack", title: "Mail")
    static let calendar = SidebarItem(systemName: "calendar", title: "Calendar")
    static let stocks = SidebarItem(systemName: "chart.line.uptrend.xyaxis", title: "Markets")
    static let saved = SidebarItem(systemName: "bookmark", title: "Saved")
    static let settings = SidebarItem(systemName: "gearshape", title: "Settings")

    static let defaults: [SidebarItem] = [
        .home,
        .search,
        .mail,
        .calendar,
        .stocks,
        .saved,
        .settings,
    ]
}

private extension String {
    var isHighPriorityCalendarTitle: Bool {
        let normalizedTitle = lowercased()
        return ["exam", "midterm", "final", "quiz", "deadline"].contains {
            normalizedTitle.contains($0)
        }
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }

    func glassSurface(cornerRadius: CGFloat) -> some View {
        background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .background(AppColor.black.opacity(0.28), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColor.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 18)
    }

    func liquidGlassButton(isHovered: Bool, cornerRadius: CGFloat) -> some View {
        background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .background(
                LinearGradient(
                    colors: [
                        AppColor.orange.opacity(isHovered ? 0.48 : 0.34),
                        AppColor.white.opacity(isHovered ? 0.14 : 0.09),
                        AppColor.black.opacity(isHovered ? 0.22 : 0.18),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                AppColor.white.opacity(isHovered ? 0.64 : 0.48),
                                AppColor.orange.opacity(0.24),
                                AppColor.white.opacity(isHovered ? 0.36 : 0.24),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(AppColor.white.opacity(isHovered ? 0.32 : 0.22))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
            .shadow(color: AppColor.orange.opacity(isHovered ? 0.22 : 0.12), radius: 10, x: -3, y: -3)
            .shadow(color: .black.opacity(isHovered ? 0.22 : 0.16), radius: 14, x: 0, y: 10)
    }
}

private struct CursorModifier: ViewModifier {
    let cursor: NSCursor

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover(perform: updateCursor)
            .onDisappear(perform: restoreCursorIfNeeded)
    }

    private func updateCursor(isHovering: Bool) {
        if isHovering {
            cursor.push()
            self.isHovering = true
        } else {
            restoreCursorIfNeeded()
        }
    }

    private func restoreCursorIfNeeded() {
        guard isHovering else { return }

        NSCursor.pop()
        isHovering = false
    }
}

private struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configureWindow(window)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            configureWindow(window)
        }
    }

    private func configureWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.styleMask.remove([.titled, .closable, .miniaturizable])
        window.styleMask.insert(.fullSizeContentView)
    }
}

private enum AppColor {
    static let black = Color(red: 0, green: 0, blue: 0)
    static let orange = Color(red: 1, green: 1, blue: 1)
    static let white = Color(red: 1, green: 1, blue: 1)
}

private enum Layout {
    static let minimumWindowWidth: CGFloat = 1460
    static let minimumWindowHeight: CGFloat = 680
    static let windowPadding: CGFloat = 34

    static let sidebarSpacing: CGFloat = 14
    static let sidebarItemSpacing: CGFloat = 16
    static let sidebarButtonSize: CGFloat = 34
    static let sidebarCornerRadius: CGFloat = 24
    static let sidebarVerticalPadding: CGFloat = 18
    static let sidebarHorizontalPadding: CGFloat = 8

    static let panelWidth: CGFloat = 760
    static let panelHeight: CGFloat = 560
    static let homePanelWidth: CGFloat = 560
    static let homePanelHeight: CGFloat = 540
    static let panelSpacing: CGFloat = 18
    static let panelPadding: CGFloat = 22
    static let panelCornerRadius: CGFloat = 24

    static let headerSpacing: CGFloat = 12
    static let headerButtonSize: CGFloat = 30
    static let appIconSize: CGFloat = 28

    static let promptHeight: CGFloat = 46
    static let promptCornerRadius: CGFloat = 14
    static let promptHorizontalPadding: CGFloat = 16

    static let rowSpacing: CGFloat = 12
    static let chatMessageSpacing: CGFloat = 10
    static let chatTranscriptHeight: CGFloat = 120
    static let contextCardHeight: CGFloat = 70
    static let contextGridColumns = [
        GridItem(.flexible(), spacing: rowSpacing),
        GridItem(.flexible(), spacing: rowSpacing),
    ]
    static let contentRowSpacing: CGFloat = 12
    static let contentRowPadding: CGFloat = 12
    static let contentRowCornerRadius: CGFloat = 14
    static let contentIconSize: CGFloat = 32
    static let contentTextSpacing: CGFloat = 2

    static let contentAreaWidth: CGFloat = 1250
    static let contentAreaHeight: CGFloat = 560

    static let browserWorkspaceWidth: CGFloat = 1250
    static let browserIslandSpacing: CGFloat = 14
    static let browserPanelWidth: CGFloat = 900
    static let browserChatWidth: CGFloat = 336
    static let browserPanelPadding: CGFloat = 14
    static let browserChatPadding: CGFloat = 18

    static let searchPanelWidth: CGFloat = 760
    static let searchPanelSpacing: CGFloat = 40
    static let searchCornerRadius: CGFloat = 16
    static let searchFieldHeight: CGFloat = 56
    static let searchFieldSpacing: CGFloat = 14
    static let searchFieldHorizontalPadding: CGFloat = 24
    static let searchHeaderHeight: CGFloat = 72
    static let searchTokenSize: CGFloat = 34
    static let searchEmptyStateHeight: CGFloat = 330
    static let searchEmptyStateSpacing: CGFloat = 14
    static let searchEmptyIconSize: CGFloat = 62
    static let searchEmptyTextWidth: CGFloat = 450
    static let searchClearButtonHeight: CGFloat = 40
    static let searchFooterHeight: CGFloat = 64
    static let searchFooterSpacing: CGFloat = 20
    static let searchFooterHorizontalPadding: CGFloat = 24
    static let searchFooterKeySize: CGFloat = 32
    static let keyboardShortcutWidth: CGFloat = 36
    static let keyboardShortcutHeight: CGFloat = 30
}

#Preview {
    ContentView()
}

//
//  KnowledgeGraph.swift
//  Friday
//
//  Created by Ved Panse on 5/22/26.
//

import Combine
import Foundation
import AppKit
import Security
import SwiftUI

protocol Node: AnyObject, Identifiable {
    var id: String { get }
    var label: String { get set }
    var path: URL? { get set }
    var done: Bool { get set }
    var description: String { get set }
    var children: [any Node]? { get set }
}

final class TopicNode: Node {
    let id: String
    var label = ""
    var path: URL?
    var done = false
    var description = ""
    var children: [any Node]? = []

    init(id: String = UUID().uuidString) {
        self.id = id
    }

    convenience init(label: String, description: String = "", children: [any Node] = []) {
        self.init()
        self.label = label
        self.description = description
        self.children = children
    }

    func addChild(_ node: any Node) {
        if children == nil {
            children = [node]
        } else {
            children?.append(node)
        }
    }
}

final class ConceptNode: Node {
    let id: String
    var label = ""
    var path: URL?
    var done = false
    var description = ""
    var children: [any Node]? {
        get { nil }
        set { }
    }
    let createdAt = Date()

    init(id: String = UUID().uuidString) {
        self.id = id
    }

    convenience init(label: String, description: String = "") {
        self.init()
        self.label = label
        self.description = description
    }
}

final class KnowledgeGraph: ObservableObject {
    @Published var topics: [TopicNode] = []
    @Published var generatedTopic: String?
    @Published var generatedDepth: KnowledgeGraphUnderstandingDepth?

    private let store: KnowledgeGraphStore
    private var rawOpenAIResponse: String?

    convenience init() {
        self.init(store: KnowledgeGraphStore())
    }

    private init(store: KnowledgeGraphStore) {
        self.store = store
        if let snapshot = store.load() {
            topics = snapshot.topics.map(Self.topicNode(from:))
            generatedTopic = snapshot.topic
            generatedDepth = snapshot.depth.flatMap(KnowledgeGraphUnderstandingDepth.init(rawValue:))
            rawOpenAIResponse = snapshot.rawOpenAIResponse
        }
    }

    func replace(with generatedGraph: GeneratedKnowledgeGraph, topic: String, depth: KnowledgeGraphUnderstandingDepth, rawResponse: String) {
        topics = generatedGraph.topics.map(Self.topicNode(from:))
        generatedTopic = topic
        generatedDepth = depth
        self.rawOpenAIResponse = rawResponse
        save(rawResponse: rawResponse)
    }

    func addTopic(_ topic: TopicNode) {
        topics.append(topic)
        save(rawResponse: nil)
    }

    func setDone(_ isDone: Bool, forNodeID nodeID: String) {
        guard let node = findNode(withID: nodeID) else { return }
        objectWillChange.send()
        setDone(isDone, for: node)
        save(rawResponse: nil)
    }

    func save(rawResponse: String?) {
        if let rawResponse {
            self.rawOpenAIResponse = rawResponse
        }

        let snapshot = KnowledgeGraphSnapshot(
            version: 1,
            topic: generatedTopic,
            depth: generatedDepth?.rawValue,
            generatedAt: Date(),
            rawOpenAIResponse: self.rawOpenAIResponse,
            topics: topics.map(Self.codableNode(from:))
        )
        store.save(snapshot)
    }

    private func findNode(withID nodeID: String) -> (any Node)? {
        for topic in topics {
            if topic.id == nodeID {
                return topic
            }

            if let node = findNode(withID: nodeID, in: topic.children ?? []) {
                return node
            }
        }

        return nil
    }

    private func findNode(withID nodeID: String, in nodes: [any Node]) -> (any Node)? {
        for node in nodes {
            if node.id == nodeID {
                return node
            }

            if let child = findNode(withID: nodeID, in: node.children ?? []) {
                return child
            }
        }

        return nil
    }

    private func setDone(_ isDone: Bool, for node: any Node) {
        node.done = isDone

        for child in node.children ?? [] {
            setDone(isDone, for: child)
        }
    }

    private static func topicNode(from node: KnowledgeGraphCodableNode) -> TopicNode {
        let topic = TopicNode(id: node.id)
        topic.label = node.label
        topic.description = node.description
        topic.done = node.done
        topic.children = node.children.map { child in
            if child.children.isEmpty {
                let concept = ConceptNode(id: child.id)
                concept.label = child.label
                concept.description = child.description
                concept.done = child.done
                return concept
            }

            return topicNode(from: child)
        }
        return topic
    }

    private static func codableNode(from node: any Node) -> KnowledgeGraphCodableNode {
        KnowledgeGraphCodableNode(
            id: node.id,
            label: node.label,
            description: node.description,
            done: node.done,
            children: (node.children ?? []).map(Self.codableNode(from:))
        )
    }
}

enum KnowledgeGraphUnderstandingDepth: String, CaseIterable, Codable, Identifiable {
    case surface
    case medium
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .surface:
            return "Surface level"
        case .medium:
            return "Medium"
        case .deep:
            return "Deep"
        }
    }

    var generationGuidance: String {
        switch self {
        case .surface:
            return "Create 3 to 4 top-level topics. Each topic should have 3 to 5 practical leaf concepts. Keep the graph compact."
        case .medium:
            return "Create 4 to 6 top-level topics. Include useful subtopics where needed, with 4 to 7 leaf concepts per major area."
        case .deep:
            return "Create 6 to 8 top-level topics. Include multiple layers of subtopics and detailed prerequisite and advanced concepts."
        }
    }
}

struct GeneratedKnowledgeGraph {
    let topics: [KnowledgeGraphCodableNode]
}

private struct KnowledgeGraphGenerationResult {
    let graph: GeneratedKnowledgeGraph
    let rawResponse: String
}

private struct KnowledgeGraphSnapshot: Codable {
    let version: Int
    let topic: String?
    let depth: String?
    let generatedAt: Date
    let rawOpenAIResponse: String?
    let topics: [KnowledgeGraphCodableNode]
}

struct KnowledgeGraphCodableNode: Codable, Equatable {
    var id = UUID().uuidString
    var label: String
    var description: String
    var done = false
    var children: [KnowledgeGraphCodableNode] = []

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case description
        case done
        case children
    }

    init(
        id: String = UUID().uuidString,
        label: String,
        description: String,
        done: Bool = false,
        children: [KnowledgeGraphCodableNode] = []
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.done = done
        self.children = children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try container.decode(String.self, forKey: .label)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        children = try container.decodeIfPresent([KnowledgeGraphCodableNode].self, forKey: .children) ?? []
    }
}

private struct KnowledgeGraphStore {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Friday", directoryHint: .isDirectory)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Friday", directoryHint: .isDirectory)

        fileURL = baseURL.appending(path: "knowledge-graph.json", directoryHint: .notDirectory)
    }

    func load() -> KnowledgeGraphSnapshot? {
        guard
            let data = try? Data(contentsOf: fileURL),
            let snapshot = try? JSONDecoder.knowledgeGraph.decode(KnowledgeGraphSnapshot.self, from: data)
        else {
            return nil
        }

        return snapshot
    }

    func save(_ snapshot: KnowledgeGraphSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.knowledgeGraph.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("Friday failed to save knowledge graph: \(error.localizedDescription)")
        }
    }
}

private struct KnowledgeGraphOpenAIClient {
    func generateGraph(
        topic: String,
        depth: KnowledgeGraphUnderstandingDepth
    ) async throws -> KnowledgeGraphGenerationResult {
        let apiKey = (KnowledgeGraphKeychain.openAIAPIKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw KnowledgeGraphGenerationError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(topic: topic, depth: depth))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw KnowledgeGraphGenerationError.openAIRequestFailed
        }

        let text = Self.extractText(from: data)
        guard !text.isEmpty else {
            throw KnowledgeGraphGenerationError.emptyResponse
        }

        let graph = try Self.decodeGraph(from: text, rootTopic: topic)
        return KnowledgeGraphGenerationResult(graph: graph, rawResponse: text)
    }

    private func requestBody(topic: String, depth: KnowledgeGraphUnderstandingDepth) -> [String: Any] {
        [
            "model": "gpt-5.4-mini",
            "max_output_tokens": 4000,
            "instructions": """
            You generate learning knowledge graphs. Return only valid JSON. Do not wrap it in markdown.
            The app will create exactly one root node using the user's topic text.
            Your top-level "topics" array must contain subtopics that belong under that root.
            Do not include the user's topic itself as one of the top-level items unless it is the only object needed to hold children.
            The JSON shape must be:
            {
              "topics": [
                {
                  "label": "Subtopic name",
                  "description": "One sentence about why this subtopic matters.",
                  "children": [
                    {
                      "label": "Concept name",
                      "description": "One sentence explanation.",
                      "children": []
                    }
                  ]
                }
              ]
            }
            Non-leaf nodes represent topics or subtopics and must have children.
            Leaf nodes represent concepts and must use "children": [].
            The top-level array may have multiple subtopics, but there must not be multiple root topics.
            Keep labels short and descriptions practical.
            """,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": """
                            Topic to learn: \(topic)
                            Desired understanding: \(depth.title)
                            Graph detail: \(depth.generationGuidance)
                            """,
                        ],
                    ],
                ] as [String: Any],
            ],
        ]
    }

    private static func decodeGraph(from text: String, rootTopic: String) throws -> GeneratedKnowledgeGraph {
        let cleanedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)

        guard let data = cleanedText.data(using: .utf8) else {
            throw KnowledgeGraphGenerationError.invalidResponse
        }

        let response = try JSONDecoder.knowledgeGraph.decode(GeneratedKnowledgeGraphResponse.self, from: data)
        let generatedTopics = response.topics
            .map(Self.normalizedNode(_:))
            .filter { !$0.label.isEmpty }

        guard !generatedTopics.isEmpty else {
            throw KnowledgeGraphGenerationError.invalidResponse
        }

        let rootDescription = generatedTopics.count == 1 && labelsMatch(generatedTopics[0].label, rootTopic)
            ? generatedTopics[0].description
            : "A learning plan for \(rootTopic)."
        let rootChildren = generatedTopics.count == 1 && labelsMatch(generatedTopics[0].label, rootTopic)
            ? generatedTopics[0].children
            : generatedTopics
        let root = KnowledgeGraphCodableNode(
            label: rootTopic,
            description: rootDescription,
            children: rootChildren
        )

        return GeneratedKnowledgeGraph(topics: [root])
    }

    private static func normalizedNode(_ node: KnowledgeGraphCodableNode) -> KnowledgeGraphCodableNode {
        KnowledgeGraphCodableNode(
            id: node.id,
            label: node.label.trimmingCharacters(in: .whitespacesAndNewlines),
            description: node.description.trimmingCharacters(in: .whitespacesAndNewlines),
            done: node.done,
            children: node.children.map(normalizedNode(_:)).filter { !$0.label.isEmpty }
        )
    }

    private static func labelsMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
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

private struct GeneratedKnowledgeGraphResponse: Decodable {
    let topics: [KnowledgeGraphCodableNode]
}

private enum KnowledgeGraphGenerationError: LocalizedError {
    case missingAPIKey
    case openAIRequestFailed
    case emptyResponse
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI API key in Settings before generating a learning graph."
        case .openAIRequestFailed:
            return "OpenAI could not generate the graph right now. Check the API key and network connection."
        case .emptyResponse:
            return "OpenAI returned an empty graph response."
        case .invalidResponse:
            return "OpenAI returned a graph format Friday could not read."
        }
    }
}

private enum KnowledgeGraphKeychain {
    private static let service = "com.vedpanse.Friday"
    private static let openAIAccount = "openai-api-key"

    static var openAIAPIKey: String? {
        read(account: openAIAccount)
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
}

struct KnowledgeGraphPanel: View {
    @StateObject private var graph = KnowledgeGraph()
    @State private var selectedNodeID: String?
    @State private var isShowingGenerateDialog = false
    @State private var requestedTopic = ""
    @State private var requestedDepth = KnowledgeGraphUnderstandingDepth.medium
    @State private var generationError: String?
    @State private var isGenerating = false
    @State private var isAddButtonCursorPushed = false

    private var layout: KnowledgeGraphLayout {
        KnowledgeGraphLayout(graph: graph)
    }

    var body: some View {
        let layout = layout

        HStack(alignment: .top, spacing: 16) {
            graphIsland(layout: layout)

            if let selectedNode = layout.nodes.first(where: { $0.id == selectedNodeID }) {
                KnowledgeGraphNodeDetailsIsland(
                    node: selectedNode,
                    relatedNodes: relatedNodes(for: selectedNode, in: layout),
                    setDone: { isDone in
                        graph.setDone(isDone, forNodeID: selectedNode.id)
                    },
                    close: {
                        selectedNodeID = nil
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: selectedNodeID)
        .background(WindowBackgroundDraggingOverride(isMovableByWindowBackground: false))
        .sheet(isPresented: $isShowingGenerateDialog) {
            generateGraphDialog
        }
    }

    private func graphIsland(layout: KnowledgeGraphLayout) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(red: 0.095, green: 0.095, blue: 0.095))

            KnowledgeGraphCanvas(
                nodes: layout.nodes,
                edges: layout.edges,
                selectedNodeID: $selectedNodeID,
                passthroughHitRegions: { size in
                    [
                        CGRect(
                            x: size.width - 88,
                            y: 0,
                            width: 88,
                            height: 88
                        ),
                    ]
                }
            )

            if layout.nodes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    Text("Create a learning graph")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Use the plus button to generate topics, subtopics, and concepts.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .allowsHitTesting(false)
            }

            graphHeader
                .padding(22)

            addTopicButton
                .padding(22)
        }
        .frame(width: 980, height: 680)
        .knowledgeGraphGlass(cornerRadius: 28)
    }

    private var graphHeader: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Knowledge Graph")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Topics branch into topics or leaf concepts.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.52))
                }

                Spacer()
            }

            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var addTopicButton: some View {
        VStack {
            HStack {
                Spacer()

                Button {
                    generationError = nil
                    requestedTopic = graph.generatedTopic ?? ""
                    requestedDepth = graph.generatedDepth ?? .medium
                    isShowingGenerateDialog = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .knowledgeGraphCircularGlass()
                .accessibilityLabel("Add topic")
                .onHover { isHovering in
                    updateAddButtonCursor(isHovering: isHovering)
                }
                .onDisappear {
                    restoreAddButtonCursorIfNeeded()
                }
            }

            Spacer()
        }
    }

    private func updateAddButtonCursor(isHovering: Bool) {
        if isHovering {
            guard !isAddButtonCursorPushed else { return }
            NSCursor.pointingHand.push()
            isAddButtonCursorPushed = true
        } else {
            restoreAddButtonCursorIfNeeded()
        }
    }

    private func restoreAddButtonCursorIfNeeded() {
        guard isAddButtonCursorPushed else { return }
        NSCursor.pop()
        isAddButtonCursorPushed = false
    }

    private var generateGraphDialog: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generate Learning Graph")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Friday will replace the current graph with an OpenAI-generated plan.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Topic")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))

                TextField("What do you want to learn?", text: $requestedTopic)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Understanding")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Picker("Understanding", selection: $requestedDepth) {
                    ForEach(KnowledgeGraphUnderstandingDepth.allCases) { depth in
                        Text(depth.title).tag(depth)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if let generationError {
                Text(generationError)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red.opacity(0.92))
            }

            HStack {
                Button("Cancel") {
                    isShowingGenerateDialog = false
                }
                .disabled(isGenerating)

                Spacer()

                Button {
                    generateGraph()
                } label: {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Generate")
                    }
                }
                .disabled(isGenerating || requestedTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
    }

    private func generateGraph() {
        let topic = requestedTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return }

        isGenerating = true
        generationError = nil

        Task {
            do {
                let result = try await KnowledgeGraphOpenAIClient().generateGraph(topic: topic, depth: requestedDepth)
                await MainActor.run {
                    graph.replace(with: result.graph, topic: topic, depth: requestedDepth, rawResponse: result.rawResponse)
                    selectedNodeID = nil
                    isGenerating = false
                    isShowingGenerateDialog = false
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func relatedNodes(
        for node: KnowledgeGraphDisplayNode,
        in layout: KnowledgeGraphLayout
    ) -> [KnowledgeGraphRelatedNode] {
        let parents = layout.edges.compactMap { edge -> KnowledgeGraphRelatedNode? in
            guard
                edge.childID == node.id,
                let parent = layout.nodes.first(where: { $0.id == edge.parentID })
            else {
                return nil
            }

            return KnowledgeGraphRelatedNode(role: "Parent", node: parent)
        }

        let children = layout.edges.compactMap { edge -> KnowledgeGraphRelatedNode? in
            guard
                edge.parentID == node.id,
                let child = layout.nodes.first(where: { $0.id == edge.childID })
            else {
                return nil
            }

            return KnowledgeGraphRelatedNode(role: "Child", node: child)
        }

        return parents + children
    }
}

private struct KnowledgeGraphCanvas: View {
    let nodes: [KnowledgeGraphDisplayNode]
    let edges: [KnowledgeGraphEdge]
    @Binding var selectedNodeID: String?
    let passthroughHitRegions: (CGSize) -> [CGRect]

    private let graphPositionMin: CGFloat = -0.34
    private let graphPositionMax: CGFloat = 1.34
    private let graphCoordinateSpace = "KnowledgeGraphCanvasCoordinateSpace"

    @State private var nodePositions: [String: UnitPoint] = [:]
    @State private var panOffset = CGSize.zero
    @State private var lastPanOffset = CGSize.zero
    @State private var zoom: CGFloat = 1
    @State private var lastGestureZoom: CGFloat = 1
    @State private var activeDraggedNodeID: String?
    @State private var dragPointerOffsets: [String: CGSize] = [:]
    @State private var nodeVelocities: [String: CGSize] = [:]
    @State private var simulationAlpha: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                KnowledgeGraphInteractionView(
                    nodeHitRegions: nodeHitRegions(in: geometry.size),
                    passthroughHitRegions: passthroughHitRegions(geometry.size),
                    onScroll: { delta, location in
                        zoom(by: delta, around: location, in: geometry.size)
                    },
                    onPanChanged: { translation in
                        panGraph(by: translation)
                    },
                    onPanEnded: {
                        finishGraphPan()
                    },
                    onKeyboardPan: { offset in
                        nudgeGraph(by: offset)
                    },
                    onKeyboardZoom: { multiplier in
                        zoomByKeyboard(multiplier, in: geometry.size)
                    }
                )

                Canvas { context, size in
                    for edge in edges {
                        guard
                            let parent = nodes.first(where: { $0.id == edge.parentID }),
                            let child = nodes.first(where: { $0.id == edge.childID })
                        else {
                            continue
                        }

                        var path = Path()
                        path.move(to: screenPoint(for: parent, in: size))
                        path.addLine(to: screenPoint(for: child, in: size))
                        context.stroke(path, with: .color(.white.opacity(0.13)), lineWidth: 0.9)
                    }
                }

                ForEach(nodes) { node in
                    KnowledgeGraphNodeView(
                        node: node,
                        isSelected: selectedNodeID == node.id,
                        isDragging: activeDraggedNodeID == node.id,
                        zoom: zoom,
                        select: {
                            selectedNodeID = node.id
                        },
                        dragChanged: { value in
                            activeDraggedNodeID = node.id
                            move(node, dragValue: value, in: geometry.size)
                        },
                        dragEnded: {
                            dragPointerOffsets[node.id] = nil
                            simulationAlpha = max(simulationAlpha, 0.18)
                            activeDraggedNodeID = nil
                        }
                    ) {
                        selectedNodeID = node.id
                    }
                    .position(screenPoint(for: node, in: geometry.size))
                    .transaction { transaction in
                        if activeDraggedNodeID == node.id {
                            transaction.animation = nil
                        }
                    }
                }
            }
            .coordinateSpace(name: graphCoordinateSpace)
            .contentShape(Rectangle())
            .simultaneousGesture(zoomGesture(in: geometry.size))
            .onAppear {
                seedNodePositionsIfNeeded()
            }
            .onChange(of: nodes) { _, _ in
                seedNodePositionsIfNeeded()
            }
            .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
                tickSimulation(in: geometry.size)
            }
            .clipped()
        }
    }

    private func panGraph(by translation: CGSize) {
        guard activeDraggedNodeID == nil else { return }
        panOffset = CGSize(
            width: lastPanOffset.width + translation.width,
            height: lastPanOffset.height + translation.height
        )
    }

    private func finishGraphPan() {
        guard activeDraggedNodeID == nil else { return }
        lastPanOffset = panOffset
    }

    private func nudgeGraph(by offset: CGSize) {
        guard activeDraggedNodeID == nil else { return }
        panOffset = CGSize(
            width: panOffset.width + offset.width,
            height: panOffset.height + offset.height
        )
        lastPanOffset = panOffset
    }

    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let nextZoom = clampedZoom(lastGestureZoom * value)
                zoomAroundCenter(nextZoom, in: size)
            }
            .onEnded { _ in
                lastGestureZoom = zoom
            }
    }

    private func seedNodePositionsIfNeeded() {
        var positions = nodePositions
        var velocities = nodeVelocities
        for node in nodes where positions[node.id] == nil {
            positions[node.id] = jitteredPosition(for: node)
            velocities[node.id] = .zero
        }
        nodePositions = positions
        nodeVelocities = velocities
        simulationAlpha = max(simulationAlpha, 0.9)
    }

    private func screenPoint(for node: KnowledgeGraphDisplayNode, in size: CGSize) -> CGPoint {
        let worldPoint = (nodePositions[node.id] ?? node.position).point(in: size)
        return CGPoint(
            x: worldPoint.x * zoom + panOffset.width,
            y: worldPoint.y * zoom + panOffset.height
        )
    }

    private func nodeHitRegions(in size: CGSize) -> [CGRect] {
        nodes.map { node in
            let point = screenPoint(for: node, in: size)
            let width: CGFloat = node.kind == .topic ? 92 : 78
            let height: CGFloat = shouldShowLabels ? 96 : 44
            return CGRect(
                x: point.x - width / 2,
                y: point.y - 26,
                width: width,
                height: height
            )
        }
    }

    private var shouldShowLabels: Bool {
        zoom >= 0.68
    }

    private func move(_ node: KnowledgeGraphDisplayNode, dragValue: DragGesture.Value, in size: CGSize) {
        if dragPointerOffsets[node.id] == nil {
            let nodePoint = screenPoint(for: node, in: size)
            dragPointerOffsets[node.id] = CGSize(
                width: nodePoint.x - dragValue.startLocation.x,
                height: nodePoint.y - dragValue.startLocation.y
            )
        }

        let pointerOffset = dragPointerOffsets[node.id] ?? .zero
        let nextScreenPoint = CGPoint(
            x: dragValue.location.x + pointerOffset.width,
            y: dragValue.location.y + pointerOffset.height
        )
        let nextPosition = UnitPoint(
            x: clamp((nextScreenPoint.x - panOffset.width) / max(size.width * zoom, 1), min: graphPositionMin, max: graphPositionMax),
            y: clamp((nextScreenPoint.y - panOffset.height) / max(size.height * zoom, 1), min: graphPositionMin, max: graphPositionMax)
        )
        nodePositions[node.id] = nextPosition
        nodeVelocities[node.id] = .zero
        simulationAlpha = max(simulationAlpha, 0.45)
    }

    private func tickSimulation(in size: CGSize) {
        guard size.width > 0, size.height > 0, !nodes.isEmpty else { return }
        guard simulationAlpha > 0.012 || activeDraggedNodeID != nil else { return }

        var positions = nodePositions
        var velocities = nodeVelocities
        var forces = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, CGSize.zero) })
        let worldPositions = Dictionary(uniqueKeysWithValues: nodes.map { node in
            let position = positions[node.id] ?? node.position
            return (node.id, position.point(in: size))
        })

        for leftIndex in nodes.indices {
            for rightIndex in nodes.index(after: leftIndex)..<nodes.endIndex {
                let left = nodes[leftIndex]
                let right = nodes[rightIndex]
                guard
                    let leftPoint = worldPositions[left.id],
                    let rightPoint = worldPositions[right.id]
                else {
                    continue
                }

                let dx = rightPoint.x - leftPoint.x
                let dy = rightPoint.y - leftPoint.y
                let distance = max(hypot(dx, dy), 1)
                guard distance < 380 else { continue }

                let magnitude = 5200 / (distance * distance)
                let force = CGSize(width: dx / distance * magnitude, height: dy / distance * magnitude)
                forces[left.id, default: .zero].width -= force.width
                forces[left.id, default: .zero].height -= force.height
                forces[right.id, default: .zero].width += force.width
                forces[right.id, default: .zero].height += force.height
            }
        }

        for edge in edges {
            guard
                let parent = nodes.first(where: { $0.id == edge.parentID }),
                let child = nodes.first(where: { $0.id == edge.childID }),
                let parentPoint = worldPositions[parent.id],
                let childPoint = worldPositions[child.id]
            else {
                continue
            }

            let dx = childPoint.x - parentPoint.x
            let dy = childPoint.y - parentPoint.y
            let distance = max(hypot(dx, dy), 1)
            let desiredDistance = parent.kind == .topic && child.kind == .topic ? 220.0 : 170.0
            let magnitude = (distance - desiredDistance) * 0.014
            let force = CGSize(width: dx / distance * magnitude, height: dy / distance * magnitude)
            forces[parent.id, default: .zero].width += force.width
            forces[parent.id, default: .zero].height += force.height
            forces[child.id, default: .zero].width -= force.width
            forces[child.id, default: .zero].height -= force.height
        }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for node in nodes {
            guard let point = worldPositions[node.id] else { continue }
            forces[node.id, default: .zero].width += (center.x - point.x) * 0.0012
            forces[node.id, default: .zero].height += (center.y - point.y) * 0.0012
        }

        let friction: CGFloat = 0.82
        let maxVelocity: CGFloat = 10
        for node in nodes {
            if activeDraggedNodeID == node.id {
                velocities[node.id] = .zero
                continue
            }

            let force = forces[node.id] ?? .zero
            var velocity = velocities[node.id] ?? .zero
            velocity.width = (velocity.width + force.width * simulationAlpha) * friction
            velocity.height = (velocity.height + force.height * simulationAlpha) * friction
            velocity = clampedVelocity(velocity, maxVelocity: maxVelocity)

            let current = positions[node.id] ?? node.position
            positions[node.id] = UnitPoint(
                x: clamp(current.x + velocity.width / size.width, min: graphPositionMin, max: graphPositionMax),
                y: clamp(current.y + velocity.height / size.height, min: graphPositionMin, max: graphPositionMax)
            )
            velocities[node.id] = velocity
        }

        nodePositions = positions
        nodeVelocities = velocities
        simulationAlpha *= activeDraggedNodeID == nil ? 0.986 : 0.996
    }

    private func clampedVelocity(_ velocity: CGSize, maxVelocity: CGFloat) -> CGSize {
        let speed = hypot(velocity.width, velocity.height)
        guard speed > maxVelocity else { return velocity }
        return CGSize(
            width: velocity.width / speed * maxVelocity,
            height: velocity.height / speed * maxVelocity
        )
    }

    private func jitteredPosition(for node: KnowledgeGraphDisplayNode) -> UnitPoint {
        let hash = abs(node.id.hashValue)
        let xJitter = CGFloat(hash % 41 - 20) / 1000
        let yJitter = CGFloat((hash / 41) % 41 - 20) / 1000
        return UnitPoint(
            x: clamp(node.position.x + xJitter, min: graphPositionMin, max: graphPositionMax),
            y: clamp(node.position.y + yJitter, min: graphPositionMin, max: graphPositionMax)
        )
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private func zoom(by scrollDelta: CGFloat, around location: CGPoint, in size: CGSize) {
        let zoomFactor = exp(scrollDelta * 0.0018)
        let nextZoom = clampedZoom(zoom * zoomFactor)
        setZoom(nextZoom, around: location, in: size)
        lastGestureZoom = zoom
    }

    private func zoomAroundCenter(_ nextZoom: CGFloat, in size: CGSize) {
        setZoom(nextZoom, around: CGPoint(x: size.width / 2, y: size.height / 2), in: size)
    }

    private func zoomByKeyboard(_ multiplier: CGFloat, in size: CGSize) {
        let nextZoom = clampedZoom(zoom * multiplier)
        zoomAroundCenter(nextZoom, in: size)
        lastGestureZoom = zoom
    }

    private func setZoom(_ nextZoom: CGFloat, around focus: CGPoint, in size: CGSize) {
        guard zoom != nextZoom else { return }

        let worldFocus = CGPoint(
            x: (focus.x - panOffset.width) / zoom,
            y: (focus.y - panOffset.height) / zoom
        )

        zoom = nextZoom
        panOffset = CGSize(
            width: focus.x - worldFocus.x * nextZoom,
            height: focus.y - worldFocus.y * nextZoom
        )
        lastPanOffset = panOffset
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.45), 2.8)
    }
}

private struct KnowledgeGraphNodeDetailsIsland: View {
    let node: KnowledgeGraphDisplayNode
    let relatedNodes: [KnowledgeGraphRelatedNode]
    let setDone: (Bool) -> Void
    let close: () -> Void

    @State private var isCloseHovered = false
    @State private var isCheckboxCursorPushed = false

    private var typeLabel: String {
        switch node.kind {
        case .topic:
            return "Topic"
        case .concept:
            return "Concept"
        }
    }

    private var nodeColor: Color {
        node.graphColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    setDone(!node.done)
                } label: {
                    ZStack {
                        Circle()
                            .fill(node.done ? Color.green : Color.clear)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Circle()
                                    .stroke(node.done ? Color.green : Color.secondary.opacity(0.7), lineWidth: 1.4)
                            }

                        if node.done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(node.done ? "Mark not done" : "Mark done")
                .onHover { isHovering in
                    updateCheckboxCursor(isHovering: isHovering)
                }
                Text(node.label)
            }
            Text(node.description)
                .foregroundStyle(.secondary)


            if node.kind == .topic {
                ForEach(relatedNodes) { relatedNode in
                    HStack {
                        if (relatedNode.node.done) {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                        }
                        Text(relatedNode.node.label)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 260, height: 680)
        .knowledgeGraphGlass(cornerRadius: 26)
        .onDisappear {
            restoreCheckboxCursorIfNeeded()
        }
    }

    private func updateCheckboxCursor(isHovering: Bool) {
        if isHovering {
            guard !isCheckboxCursorPushed else { return }
            NSCursor.pointingHand.push()
            isCheckboxCursorPushed = true
        } else {
            restoreCheckboxCursorIfNeeded()
        }
    }

    private func restoreCheckboxCursorIfNeeded() {
        guard isCheckboxCursorPushed else { return }
        NSCursor.pop()
        isCheckboxCursorPushed = false
    }
}

private struct KnowledgeGraphNodeView: View {
    let node: KnowledgeGraphDisplayNode
    let isSelected: Bool
    let isDragging: Bool
    let zoom: CGFloat
    let select: () -> Void
    let dragChanged: (DragGesture.Value) -> Void
    let dragEnded: () -> Void
    let action: () -> Void

    @State private var isHovered = false
    @State private var isCursorPushed = false
    @State private var isBreathing = false

    private var nodeColor: Color {
        node.graphColor
    }

    private var nodeDiameter: CGFloat {
        switch node.kind {
        case .topic:
            return node.depth == 0 ? 13 : 11
        case .concept:
            return 7
        }
    }

    private var visualScale: CGFloat {
        min(max(zoom, 0.52), 1.45)
    }

    private var shouldShowLabel: Bool {
        zoom >= 0.68
    }

    private var labelFontSize: CGFloat {
        node.kind == .topic ? 8 : 7
    }

    private var labelColor: Color {
        node.kind == .topic ? .white : Color.gray.opacity(0.86)
    }

    private var labelOffset: CGFloat {
        nodeDiameter / 2 + 16
    }

    var body: some View {
        nodeBody
            .frame(width: node.kind == .topic ? 72 : 60, height: shouldShowLabel ? 78 : 34)
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("KnowledgeGraphCanvasCoordinateSpace"))
                    .onChanged { value in
                        dragChanged(value)
                    }
                    .onEnded { _ in
                        dragEnded()
                    }
            )
            .onHover { isHovering in
                isHovered = isHovering
                updateCursor(isHovering: isHovering)
            }
            .onDisappear {
                restoreCursorIfNeeded()
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
            .scaleEffect(visualScale * (!isDragging && (isHovered || isSelected) ? 1.04 : 1))
            .animation(isDragging ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: isBreathing)
            .animation(isDragging ? nil : .easeOut(duration: 0.14), value: isHovered)
            .animation(isDragging ? nil : .easeOut(duration: 0.14), value: isSelected)
            .animation(isDragging ? nil : .easeOut(duration: 0.12), value: shouldShowLabel)
    }

    private var nodeBody: some View {
        ZStack {
            ZStack {
                Circle()
                    .fill(nodeColor.opacity(isSelected || isHovered ? 0.3 : (isBreathing && !isDragging ? 0.18 : 0.11)))
                    .frame(
                        width: nodeDiameter + (isBreathing && !isDragging ? 16 : 12),
                        height: nodeDiameter + (isBreathing && !isDragging ? 16 : 12)
                    )
                    .blur(radius: isBreathing && !isDragging ? 5 : 4)

                Circle()
                    .fill(nodeColor)
                    .frame(width: nodeDiameter, height: nodeDiameter)
                    .shadow(
                        color: nodeColor.opacity(isBreathing && !isDragging ? 0.56 : 0.38),
                        radius: isHovered && !isDragging ? 7 : (isBreathing && !isDragging ? 5 : 3)
                    )
                    .scaleEffect(isBreathing && !isDragging ? 1.04 : 0.98)
            }

            if shouldShowLabel {
                Text(node.displayLabel)
                    .font(.system(size: labelFontSize, weight: .regular))
                    .foregroundStyle(labelColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: node.kind == .topic ? 58 : 48)
                    .offset(y: labelOffset)
                    .transition(.opacity)
            }
        }
    }

    private func updateCursor(isHovering: Bool) {
        if isHovering {
            guard !isCursorPushed else { return }
            NSCursor.pointingHand.push()
            isCursorPushed = true
        } else {
            restoreCursorIfNeeded()
        }
    }

    private func restoreCursorIfNeeded() {
        guard isCursorPushed else { return }
        NSCursor.pop()
        isCursorPushed = false
    }
}

private struct KnowledgeGraphInteractionView: NSViewRepresentable {
    let nodeHitRegions: [CGRect]
    let passthroughHitRegions: [CGRect]
    let onScroll: (CGFloat, CGPoint) -> Void
    let onPanChanged: (CGSize) -> Void
    let onPanEnded: () -> Void
    let onKeyboardPan: (CGSize) -> Void
    let onKeyboardZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> GraphInteractionNSView {
        let view = GraphInteractionNSView()
        view.nodeHitRegions = nodeHitRegions
        view.passthroughHitRegions = passthroughHitRegions
        view.onScroll = onScroll
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
        view.onKeyboardPan = onKeyboardPan
        view.onKeyboardZoom = onKeyboardZoom
        return view
    }

    func updateNSView(_ nsView: GraphInteractionNSView, context: Context) {
        nsView.nodeHitRegions = nodeHitRegions
        nsView.passthroughHitRegions = passthroughHitRegions
        nsView.onScroll = onScroll
        nsView.onPanChanged = onPanChanged
        nsView.onPanEnded = onPanEnded
        nsView.onKeyboardPan = onKeyboardPan
        nsView.onKeyboardZoom = onKeyboardZoom
    }
}

private final class GraphInteractionNSView: NSView {
    var nodeHitRegions: [CGRect] = []
    var passthroughHitRegions: [CGRect] = []
    var onScroll: ((CGFloat, CGPoint) -> Void)?
    var onPanChanged: ((CGSize) -> Void)?
    var onPanEnded: (() -> Void)?
    var onKeyboardPan: ((CGSize) -> Void)?
    var onKeyboardZoom: ((CGFloat) -> Void)?

    private var eventMonitor: Any?
    private var panStartLocation: CGPoint?

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScrollMonitor()
    }

    override func removeFromSuperview() {
        removeEventMonitor()
        super.removeFromSuperview()
    }

    deinit {
        removeEventMonitor()
    }

    private func updateScrollMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel, .keyDown]) { [weak self] event in
            guard
                let self,
                let window,
                event.window === window
            else {
                return event
            }

            if event.type == .keyDown {
                return handleKeyDown(event)
            }

            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else {
                return event
            }

            guard !isPassthroughHit(at: location) else {
                panStartLocation = nil
                return event
            }

            switch event.type {
            case .scrollWheel:
                onScroll?(event.scrollingDeltaY, location)
                return nil

            case .leftMouseDown:
                guard !isNodeHit(at: location) else {
                    panStartLocation = nil
                    return event
                }

                panStartLocation = location
                return nil

            case .leftMouseDragged:
                guard let panStartLocation else {
                    return event
                }

                onPanChanged?(CGSize(
                    width: location.x - panStartLocation.x,
                    height: location.y - panStartLocation.y
                ))
                return nil

            case .leftMouseUp:
                guard panStartLocation != nil else {
                    return event
                }

                panStartLocation = nil
                onPanEnded?()
                return nil

            default:
                return event
            }
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func isNodeHit(at location: CGPoint) -> Bool {
        nodeHitRegions.contains { $0.contains(location) }
    }

    private func isPassthroughHit(at location: CGPoint) -> Bool {
        passthroughHitRegions.contains { $0.contains(location) }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 72 : 34

        switch event.keyCode {
        case 123:
            onKeyboardPan?(CGSize(width: step, height: 0))
            return nil

        case 124:
            onKeyboardPan?(CGSize(width: -step, height: 0))
            return nil

        case 125:
            onKeyboardPan?(CGSize(width: 0, height: -step))
            return nil

        case 126:
            onKeyboardPan?(CGSize(width: 0, height: step))
            return nil

        case 69:
            onKeyboardZoom?(1.12)
            return nil

        case 78:
            onKeyboardZoom?(0.89)
            return nil

        default:
            break
        }

        switch event.charactersIgnoringModifiers {
        case "+", "=":
            onKeyboardZoom?(1.12)
            return nil

        case "-":
            onKeyboardZoom?(0.89)
            return nil

        default:
            return event
        }
    }
}

private struct WindowBackgroundDraggingOverride: NSViewRepresentable {
    let isMovableByWindowBackground: Bool

    func makeNSView(context: Context) -> WindowBackgroundDraggingView {
        let view = WindowBackgroundDraggingView()
        view.isMovableByWindowBackground = isMovableByWindowBackground
        return view
    }

    func updateNSView(_ nsView: WindowBackgroundDraggingView, context: Context) {
        nsView.isMovableByWindowBackground = isMovableByWindowBackground
        nsView.applyOverride()
    }
}

private final class WindowBackgroundDraggingView: NSView {
    var isMovableByWindowBackground = false
    private var previousValue: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyOverride()
    }

    override func removeFromSuperview() {
        restorePreviousValue()
        super.removeFromSuperview()
    }

    deinit {
        restorePreviousValue()
    }

    func applyOverride() {
        guard let window else { return }

        if previousValue == nil {
            previousValue = window.isMovableByWindowBackground
        }

        window.isMovableByWindowBackground = isMovableByWindowBackground
    }

    private func restorePreviousValue() {
        guard let previousValue, let window else { return }
        window.isMovableByWindowBackground = previousValue
        self.previousValue = nil
    }
}

struct ConceptNodeView: View {
    let concept: ConceptNode

    var body: some View {
        KnowledgeGraphNodeView(
            node: KnowledgeGraphDisplayNode(
                id: concept.id,
                label: concept.label,
                description: concept.description,
                done: concept.done,
                kind: .concept,
                depth: 0,
                hasChildren: false,
                position: UnitPoint(x: 0.5, y: 0.5)
            ),
            isSelected: false,
            isDragging: false,
            zoom: 1,
            select: { },
            dragChanged: { _ in },
            dragEnded: { },
            action: { }
        )
    }
}

struct TopicNodeView: View {
    let topic: TopicNode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(topic.label)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            ForEach(KnowledgeGraphTree.flatten(topic.children ?? [])) { node in
                Text(node.displayLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }
}

private struct KnowledgeGraphLayout {
    let nodes: [KnowledgeGraphDisplayNode]
    let edges: [KnowledgeGraphEdge]

    init(graph: KnowledgeGraph) {
        let roots = graph.topics
        let rootPositions = [
            UnitPoint(x: 0.34, y: 0.44),
            UnitPoint(x: 0.74, y: 0.36),
            UnitPoint(x: 0.42, y: 0.84),
        ]

        var nodes: [KnowledgeGraphDisplayNode] = []
        var edges: [KnowledgeGraphEdge] = []

        for (index, root) in roots.enumerated() {
            let rootPosition = rootPositions[safe: index] ?? UnitPoint(x: 0.5, y: 0.5)
            Self.append(
                node: root,
                depth: 0,
                position: rootPosition,
                angleRange: Self.angleRange(forRootAt: index),
                nodes: &nodes,
                edges: &edges
            )
        }

        self.nodes = nodes
        self.edges = edges
    }

    private static func angleRange(forRootAt index: Int) -> ClosedRange<Double> {
        switch index {
        case 0:
            return 135...340
        case 1:
            return 170...405
        default:
            return 200...520
        }
    }

    private static func append(
        node: any Node,
        depth: Int,
        position: UnitPoint,
        angleRange: ClosedRange<Double>,
        nodes: inout [KnowledgeGraphDisplayNode],
        edges: inout [KnowledgeGraphEdge]
    ) {
        let kind: KnowledgeGraphDisplayNode.Kind = node is TopicNode ? .topic : .concept
        let children = node.children ?? []
        nodes.append(KnowledgeGraphDisplayNode(
            id: node.id,
            label: node.label,
            description: node.description,
            done: node.done,
            kind: kind,
            depth: depth,
            hasChildren: !children.isEmpty,
            position: position
        ))

        guard !children.isEmpty else {
            return
        }

        let step = children.count == 1
            ? 0
            : (angleRange.upperBound - angleRange.lowerBound) / Double(children.count - 1)
        let radius = 0.31 + Double(depth) * 0.11

        for (index, child) in children.enumerated() {
            let angle = (angleRange.lowerBound + step * Double(index)) * .pi / 180
            let childPosition = UnitPoint(
                x: min(max(position.x + cos(angle) * radius, -0.34), 1.34),
                y: min(max(position.y + sin(angle) * radius, -0.34), 1.34)
            )

            edges.append(KnowledgeGraphEdge(parentID: node.id, childID: child.id))
            Self.append(
                node: child,
                depth: depth + 1,
                position: childPosition,
                angleRange: (angleRange.lowerBound + step * Double(index) - 62)...(angleRange.lowerBound + step * Double(index) + 62),
                nodes: &nodes,
                edges: &edges
            )
        }
    }
}

private struct KnowledgeGraphDisplayNode: Identifiable, Equatable {
    enum Kind: Equatable {
        case topic
        case concept
    }

    let id: String
    let label: String
    let description: String
    let done: Bool
    let kind: Kind
    let depth: Int
    let hasChildren: Bool
    let position: UnitPoint

    var graphColor: Color {
        if depth == 0 {
            return KnowledgeGraphColor.root
        }

        guard hasChildren else {
            return KnowledgeGraphColor.leaf
        }

        return KnowledgeGraphColor.middleColor(forDepth: depth)
    }

    var displayLabel: String {
        label
    }
}

private struct KnowledgeGraphEdge: Equatable {
    let parentID: String
    let childID: String
}

private struct KnowledgeGraphRelatedNode: Identifiable, Equatable {
    let role: String
    let node: KnowledgeGraphDisplayNode

    var id: String {
        "\(role)-\(node.id)"
    }
}

private enum KnowledgeGraphTree {
    static func flatten(_ nodes: [any Node]) -> [KnowledgeGraphDisplayNode] {
        nodes.flatMap { node -> [KnowledgeGraphDisplayNode] in
            let kind: KnowledgeGraphDisplayNode.Kind = node is TopicNode ? .topic : .concept
            let current = KnowledgeGraphDisplayNode(
                id: node.id,
                label: node.label,
                description: node.description,
                done: node.done,
                kind: kind,
                depth: 0,
                hasChildren: !(node.children ?? []).isEmpty,
                position: UnitPoint(x: 0.5, y: 0.5)
            )
            return [current] + flatten(node.children ?? [])
        }
    }
}

private enum KnowledgeGraphColor {
    static let root = Color(red: 0.29, green: 0.18, blue: 0.86)
    static let violet = Color(red: 0.56, green: 0.25, blue: 0.95)
    static let leaf = Color.gray.opacity(0.8)

    private static let middlePalette = [
        violet,
        Color(red: 0.10, green: 0.42, blue: 0.92),
        Color(red: 0.03, green: 0.62, blue: 0.94),
        Color(red: 0.12, green: 0.68, blue: 0.28),
        Color(red: 0.95, green: 0.78, blue: 0.18),
        Color(red: 0.96, green: 0.48, blue: 0.14),
        root,
    ]

    static func middleColor(forDepth depth: Int) -> Color {
        middlePalette[(max(depth, 1) - 1) % middlePalette.count]
    }
}

private extension JSONDecoder {
    static var knowledgeGraph: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var knowledgeGraph: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension UnitPoint {
    func point(in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension View {
    func knowledgeGraphGlass(cornerRadius: CGFloat) -> some View {
        background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .background(Color.black.opacity(0.34), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 18)
    }

    func knowledgeGraphCircularGlass() -> some View {
        background(.ultraThinMaterial, in: Circle())
            .background(Color.black.opacity(0.34), in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 18)
    }
}

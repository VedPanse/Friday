//
//  KnowledgeGraph.swift
//  Friday
//
//  Created by Ved Panse on 5/22/26.
//

import Combine
import Foundation
import AppKit
import SwiftUI

protocol Node: AnyObject, Identifiable {
    var id: String { get }
    var label: String { get set }
    var path: URL? { get set }
    var done: Bool { get set }
    var children: [any Node]? { get set }
}

final class TopicNode: Node {
    let id = UUID().uuidString
    var label = ""
    var path: URL?
    var done = false
    var children: [any Node]? = []

    convenience init(label: String, children: [any Node] = []) {
        self.init()
        self.label = label
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
    let id = UUID().uuidString
    var label = ""
    var path: URL?
    var done = false
    var children: [any Node]? {
        get { nil }
        set { }
    }
    let createdAt = Date()

    convenience init(label: String) {
        self.init()
        self.label = label
    }
}

final class KnowledgeGraph: ObservableObject {
    @Published var topics: [TopicNode] = []

    static var sample: KnowledgeGraph {
        let graph = KnowledgeGraph()
        let capTheorem = ConceptNode(label: "CAP theorem")
        capTheorem.done = true

        let scalability = TopicNode(label: "Scalability", children: [
            TopicNode(label: "Distributed Systems", children: [
                capTheorem,
                ConceptNode(label: "Consistent hashing"),
                ConceptNode(label: "Quorum reads"),
                ConceptNode(label: "Leader election"),
            ]),
            TopicNode(label: "Databases", children: [
                ConceptNode(label: "Sharding"),
                ConceptNode(label: "Replication"),
                ConceptNode(label: "Indexing"),
            ]),
            ConceptNode(label: "Load balancing"),
            ConceptNode(label: "Backpressure"),
        ])

        let ai = TopicNode(label: "AI", children: [
            TopicNode(label: "Machine Learning", children: [
                ConceptNode(label: "Gradient descent"),
                ConceptNode(label: "Overfitting"),
                ConceptNode(label: "Embeddings"),
            ]),
            TopicNode(label: "Agents", children: [
                ConceptNode(label: "Planning"),
                ConceptNode(label: "Tool use"),
                ConceptNode(label: "Memory"),
                ConceptNode(label: "RAG"),
            ]),
            ConceptNode(label: "Transformers"),
        ])

        let systemDesign = TopicNode(label: "System Design", children: [
            ConceptNode(label: "Caching"),
            ConceptNode(label: "Queues"),
            ConceptNode(label: "Observability"),
            ConceptNode(label: "Rate limiting"),
        ])

        graph.topics = [scalability, ai, systemDesign]
        return graph
    }

    func addTopic(_ topic: TopicNode) {
        topics.append(topic)
    }

    func save() {
        // Persistence will be added once Friday starts learning graph nodes from user material.
    }
}

struct KnowledgeGraphPanel: View {
    @StateObject private var graph = KnowledgeGraph.sample
    @State private var selectedNodeID: String?

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
                    close: {
                        selectedNodeID = nil
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: selectedNodeID)
        .background(WindowBackgroundDraggingOverride(isMovableByWindowBackground: false))
    }

    private func graphIsland(layout: KnowledgeGraphLayout) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(red: 0.095, green: 0.095, blue: 0.095))

            KnowledgeGraphCanvas(
                nodes: layout.nodes,
                edges: layout.edges,
                selectedNodeID: $selectedNodeID
            )

            graphHeader
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
    let close: () -> Void

    @State private var isCloseHovered = false

    private var typeLabel: String {
        switch node.kind {
        case .topic:
            return "Topic"
        case .concept:
            return "Concept"
        }
    }

    private var nodeColor: Color {
        switch node.kind {
        case .topic:
            return KnowledgeGraphColor.topic
        case .concept:
            return KnowledgeGraphColor.concept
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if (node.done) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
            }
            Text(node.label)

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
        node.kind == .topic ? KnowledgeGraphColor.topic : KnowledgeGraphColor.concept
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
    let onScroll: (CGFloat, CGPoint) -> Void
    let onPanChanged: (CGSize) -> Void
    let onPanEnded: () -> Void
    let onKeyboardPan: (CGSize) -> Void
    let onKeyboardZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> GraphInteractionNSView {
        let view = GraphInteractionNSView()
        view.nodeHitRegions = nodeHitRegions
        view.onScroll = onScroll
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
        view.onKeyboardPan = onKeyboardPan
        view.onKeyboardZoom = onKeyboardZoom
        return view
    }

    func updateNSView(_ nsView: GraphInteractionNSView, context: Context) {
        nsView.nodeHitRegions = nodeHitRegions
        nsView.onScroll = onScroll
        nsView.onPanChanged = onPanChanged
        nsView.onPanEnded = onPanEnded
        nsView.onKeyboardPan = onKeyboardPan
        nsView.onKeyboardZoom = onKeyboardZoom
    }
}

private final class GraphInteractionNSView: NSView {
    var nodeHitRegions: [CGRect] = []
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
                done: concept.done,
                kind: .concept,
                depth: 0,
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
        nodes.append(KnowledgeGraphDisplayNode(
            id: node.id,
            label: node.label,
            done: node.done,
            kind: kind,
            depth: depth,
            position: position
        ))

        guard let children = node.children, !children.isEmpty else {
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
    let done: Bool
    let kind: Kind
    let depth: Int
    let position: UnitPoint

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
                done: node.done,
                kind: kind,
                depth: 0,
                position: UnitPoint(x: 0.5, y: 0.5)
            )
            return [current] + flatten(node.children ?? [])
        }
    }
}

private enum KnowledgeGraphColor {
    static let topic = Color.accentColor
    static let concept = Color.gray.opacity(0.8)
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
}

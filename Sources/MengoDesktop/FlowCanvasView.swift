import SwiftUI
import AppKit

/// Freestyle node-graph editor for a `FlowDocument`, N8N-style: horizontal
/// flow, dot-grid background, compact nodes with left/right port handles,
/// drag-from-output-port to connect. Read-only when `editable` is false.
struct FlowCanvasView: View {
    @Bindable var studio: StudioController
    let entry: FlowEntry
    let editable: Bool

    /// Live pan translation during an in-flight gesture (resets on release).
    @State private var pan: CGSize = .zero
    /// Cumulative pan across all completed gestures.
    @State private var cumulativePan: CGSize = .zero
    /// Persisted zoom across pan gestures.
    @State private var zoom: CGFloat = 1.0
    /// Live magnification during a pinch gesture.
    @State private var liveZoom: CGFloat = 1.0
    /// Drag-translation in progress, per step id (world-space delta).
    @State private var liveDrag: [String: CGSize] = [:]
    /// Effective zoom captured at the start of an in-flight node drag (see
    /// 5C audit) so a concurrent pinch can't teleport the node.
    @State private var dragZoomSnapshot: CGFloat?
    /// Step currently focused for field editing in the inspector.
    @State private var selectedStepId: String?
    /// When set, the next node tap creates an edge from this id to the tapped node.
    @State private var connectingFrom: String?
    /// Live drag-from-output-port: source step + current cursor in world coords.
    @State private var portDragSource: String?
    @State private var portDragCursor: CGPoint?
    /// Edge pending delete confirmation.
    @State private var pendingDeleteEdge: FlowDocument.Edge?

    // Node geometry — uniform so port positions and edge anchors stay in sync.
    private static let nodeWidth: CGFloat = 320
    private static let nodeHeight: CGFloat = 120
    private static let portRadius: CGFloat = 6
    private static let gridSpacing: CGFloat = 24
    private static let dotRadius: CGFloat = 1
    private static let minZoom: CGFloat = 0.4
    private static let maxZoom: CGFloat = 2.0

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                canvas
                toolbar
                zoomControls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let id = selectedStepId, studio.document?.steps.contains(where: { $0.id == id }) == true {
                Divider().overlay(Theme.separator)
                inspector(stepId: id)
                    .frame(width: 320)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Theme.paneBackground)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedStepId)
        .alert("Delete this connection?",
               isPresented: Binding(get: { pendingDeleteEdge != nil },
                                     set: { if !$0 { pendingDeleteEdge = nil } })) {
            Button("Delete", role: .destructive) {
                if let e = pendingDeleteEdge { studio.removeEdge(from: e.fromId, to: e.toId) }
                pendingDeleteEdge = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteEdge = nil }
        } message: {
            if let e = pendingDeleteEdge {
                Text("Removes the link from “\(e.fromId)” to “\(e.toId)”.")
            }
        }
    }

    // MARK: - Canvas (background + edges + nodes)

    private var canvas: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Empty-canvas hit catcher — NOT transformed, so it covers the
                // viewport regardless of zoom. Goes behind the world.
                Color(red: 12/255, green: 13/255, blue: 16/255)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .onTapGesture {
                        selectedStepId = nil
                        connectingFrom = nil
                    }

                ZStack(alignment: .topLeading) {
                    dotGrid(viewport: geo.size)
                    edgeLayer
                    rubberBandLayer
                    nodeLayer
                }
                .frame(width: 12_000, height: 8_000, alignment: .topLeading)
                // Named coordinate space — port drags report cursor location
                // in world (pre-transform) coords, which is what we want for
                // hit-testing target input ports.
                .coordinateSpace(name: "worldLayer")
                .scaleEffect(zoom * liveZoom, anchor: .topLeading)
                .offset(effectivePan)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .gesture(zoomGesture)
        }
    }

    // MARK: - Dot grid

    private func dotGrid(viewport: CGSize) -> some View {
        let z = zoom * liveZoom
        // Visible-world rect, in the canvas's local (pre-transform) coords —
        // that's also the world. Compute so the grid only paints what's on screen.
        let worldX = -effectivePan.width / z
        let worldY = -effectivePan.height / z
        let worldW = viewport.width / z
        let worldH = viewport.height / z
        let spacing = Self.gridSpacing
        let startX = floor(worldX / spacing) * spacing
        let endX   = ceil((worldX + worldW) / spacing) * spacing
        let startY = floor(worldY / spacing) * spacing
        let endY   = ceil((worldY + worldH) / spacing) * spacing

        return Canvas { context, _ in
            let r = Self.dotRadius
            // Subtle dim dot — visible but not noisy.
            let color = GraphicsContext.Shading.color(Color(red: 38/255, green: 41/255, blue: 47/255))
            var x = startX
            while x <= endX {
                var y = startY
                while y <= endY {
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: color)
                    y += spacing
                }
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Edge layer (and rubber-band while connecting)

    private var edgeLayer: some View {
        Canvas { context, _ in
            guard let doc = studio.document else { return }
            for edge in doc.edges() { drawEdge(edge, in: context, doc: doc) }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var rubberBandLayer: some View {
        if let source = portDragSource, let cursor = portDragCursor, let doc = studio.document {
            Canvas { context, _ in
                guard let from = portPoint(stepId: source, side: .output, doc: doc) else { return }
                drawHorizontalCurve(from: from, to: cursor,
                                    color: Theme.accent, opacity: 0.85,
                                    in: context, dashed: true)
            }
            .allowsHitTesting(false)
        }
    }

    private func drawEdge(_ edge: FlowDocument.Edge, in context: GraphicsContext, doc: FlowDocument) {
        guard let from = portPoint(stepId: edge.fromId, side: .output, doc: doc),
              let to   = portPoint(stepId: edge.toId,   side: .input,  doc: doc) else { return }
        let color: Color = edge.isImplicit ? Theme.mutedText : Theme.accent
        let opacity = edge.isImplicit ? 0.55 : 0.95
        drawHorizontalCurve(from: from, to: to, color: color, opacity: opacity,
                            in: context, dashed: false)
    }

    /// Right-to-left S-curve, control points horizontally biased so the curve
    /// hugs the source/target ports cleanly even when stacked vertically.
    private func drawHorizontalCurve(from: CGPoint, to: CGPoint, color: Color,
                                      opacity: Double, in context: GraphicsContext,
                                      dashed: Bool) {
        let dx = max(60, abs(to.x - from.x) * 0.55)
        let c1 = CGPoint(x: from.x + dx, y: from.y)
        let c2 = CGPoint(x: to.x - dx,   y: to.y)
        var path = Path()
        path.move(to: from)
        path.addCurve(to: to, control1: c1, control2: c2)
        let stroke = StrokeStyle(lineWidth: 2.0, lineCap: .round,
                                 dash: dashed ? [4, 4] : [])
        context.stroke(path, with: .color(color.opacity(opacity)), style: stroke)
        // Arrowhead — direction from control2 toward target so it points along the curve.
        let arrow = arrowHead(at: to, from: c2)
        context.fill(arrow, with: .color(color.opacity(opacity)))
    }

    private func arrowHead(at tip: CGPoint, from origin: CGPoint) -> Path {
        let angle = atan2(tip.y - origin.y, tip.x - origin.x)
        let size: CGFloat = 8
        let a1 = CGPoint(x: tip.x - size * cos(angle - .pi / 7),
                         y: tip.y - size * sin(angle - .pi / 7))
        let a2 = CGPoint(x: tip.x - size * cos(angle + .pi / 7),
                         y: tip.y - size * sin(angle + .pi / 7))
        var p = Path()
        p.move(to: tip); p.addLine(to: a1); p.addLine(to: a2); p.closeSubpath()
        return p
    }

    private var nodeLayer: some View {
        ZStack(alignment: .topLeading) {
            if let doc = studio.document {
                ForEach(Array(doc.steps.enumerated()), id: \.element.id) { idx, step in
                    nodeView(step: step, index: idx, doc: doc)
                }
            }
        }
    }

    // MARK: - Node placement

    @ViewBuilder
    private func nodeView(step: FlowDocument.Step, index: Int, doc: FlowDocument) -> some View {
        let basePos = doc.steps[index].position ?? FlowDocument.autoLayoutPosition(forIndex: index)
        let drag = liveDrag[step.id] ?? .zero
        let topLeft = CGPoint(x: basePos.x + drag.width, y: basePos.y + drag.height)
        let selected = selectedStepId == step.id
        let isConnectSource = connectingFrom == step.id
        let isConnecting = connectingFrom != nil && connectingFrom != step.id
        let card = N8NNodeCard(
            step: step, index: index,
            selected: selected,
            isConnectSource: isConnectSource,
            connecting: isConnecting,
            editable: editable,
            onSelect: { handleNodeTap(step.id) },
            onInputPortTap: { handleInputPortTap(step.id) },
            onOutputPortTap: { handleOutputPortTap(step.id) },
            onOutputDragChanged: editable ? { loc in
                portDragSource = step.id
                portDragCursor = loc
            } : nil,
            onOutputDragEnded: editable ? { loc in
                defer { portDragSource = nil; portDragCursor = nil }
                guard let doc = studio.document else { return }
                if let target = hitTestNodeInputHalf(at: loc, source: step.id, doc: doc) {
                    studio.addEdge(from: step.id, to: target)
                }
            } : nil,
            nodeWidth: Self.nodeWidth,
            nodeHeight: Self.nodeHeight,
            portRadius: Self.portRadius)
        .frame(width: Self.nodeWidth, height: Self.nodeHeight)
        .position(x: topLeft.x + Self.nodeWidth / 2,
                  y: topLeft.y + Self.nodeHeight / 2)
        if editable {
            card.highPriorityGesture(nodeDragGesture(stepId: step.id))
        } else {
            card
        }
    }

    private func handleNodeTap(_ stepId: String) {
        if let from = connectingFrom, from != stepId {
            studio.addEdge(from: from, to: stepId)
            connectingFrom = nil
            return
        }
        if connectingFrom == stepId { connectingFrom = nil; return }
        selectedStepId = stepId
    }

    private func handleOutputPortTap(_ stepId: String) {
        // Tapping the output port toggles connect-mode for that step (parity
        // with the inspector's Add button, for users who don't drag).
        connectingFrom = (connectingFrom == stepId) ? nil : stepId
    }

    private func handleInputPortTap(_ stepId: String) {
        // Tapping the input port while connecting from another node finishes
        // the connection. Otherwise it just selects the node (same as a click).
        if let from = connectingFrom, from != stepId {
            studio.addEdge(from: from, to: stepId)
            connectingFrom = nil
            return
        }
        selectedStepId = stepId
    }

    // MARK: - Port world coords

    private enum PortSide { case input, output }
    private func portPoint(stepId: String, side: PortSide, doc: FlowDocument) -> CGPoint? {
        guard let pos = doc.effectivePosition(of: stepId) else { return nil }
        let drag = liveDrag[stepId] ?? .zero
        let centerY = pos.y + Double(drag.height) + Double(Self.nodeHeight) / 2
        switch side {
        case .input:  return CGPoint(x: pos.x + Double(drag.width), y: centerY)
        case .output: return CGPoint(x: pos.x + Double(drag.width) + Double(Self.nodeWidth), y: centerY)
        }
    }

    // MARK: - Gestures

    /// Effective offset = cumulativePan + active pan
    private var effectivePan: CGSize {
        CGSize(width: cumulativePan.width + pan.width,
               height: cumulativePan.height + pan.height)
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in pan = CGSize(width: v.translation.width, height: v.translation.height) }
            .onEnded { v in
                pan = .zero
                cumulativePan.width += v.translation.width
                cumulativePan.height += v.translation.height
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { v in liveZoom = v }
            .onEnded { v in
                zoom = (zoom * v).clamped(to: Self.minZoom...Self.maxZoom)
                liveZoom = 1.0
            }
    }

    private func nodeDragGesture(stepId: String) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                if connectingFrom != nil { connectingFrom = nil }
                if dragZoomSnapshot == nil { dragZoomSnapshot = zoom * liveZoom }
                let z = dragZoomSnapshot ?? (zoom * liveZoom)
                liveDrag[stepId] = CGSize(width: v.translation.width / z,
                                          height: v.translation.height / z)
            }
            .onEnded { v in
                let z = dragZoomSnapshot ?? (zoom * liveZoom)
                dragZoomSnapshot = nil
                guard let doc = studio.document,
                      let idx = doc.steps.firstIndex(where: { $0.id == stepId }) else {
                    liveDrag.removeValue(forKey: stepId); return
                }
                let base = doc.steps[idx].position ?? FlowDocument.autoLayoutPosition(forIndex: idx)
                let next = FlowDocument.StepPosition(
                    x: base.x + Double(v.translation.width / z),
                    y: base.y + Double(v.translation.height / z))
                studio.updateStepPosition(id: stepId, to: next)
                liveDrag.removeValue(forKey: stepId)
            }
    }

    /// Returns the step id whose left half (input side) contains the world point,
    /// excluding the source step itself. Used to terminate a port drag.
    private func hitTestNodeInputHalf(at p: CGPoint, source: String, doc: FlowDocument) -> String? {
        for (idx, step) in doc.steps.enumerated() where step.id != source {
            let base = doc.steps[idx].position ?? FlowDocument.autoLayoutPosition(forIndex: idx)
            let drag = liveDrag[step.id] ?? .zero
            let topLeft = CGPoint(x: base.x + drag.width, y: base.y + drag.height)
            let inputRect = CGRect(x: topLeft.x - Self.portRadius * 2,
                                   y: topLeft.y,
                                   width: Self.nodeWidth / 2 + Self.portRadius * 2,
                                   height: Self.nodeHeight)
            if inputRect.contains(p) { return step.id }
        }
        return nil
    }

    // MARK: - Toolbar + zoom controls (pinned, screen-space)

    private var toolbar: some View {
        HStack(spacing: 8) {
            if let id = connectingFrom {
                Label("Click a node's input port to connect from “\(id)”", systemImage: "link.badge.plus")
                    .font(Theme.caption).foregroundStyle(Theme.accent)
                Button("Cancel") { connectingFrom = nil }
                    .buttonStyle(.plain).font(Theme.caption)
            } else {
                Text("Drag canvas to pan • Drag node to move • Drag output port to connect")
                    .font(Theme.caption).foregroundStyle(Theme.mutedText)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.cardBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
        .padding(12)
    }

    private var zoomControls: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 1) {
                    zoomButton(systemImage: "minus") {
                        zoom = (zoom - 0.2).clamped(to: Self.minZoom...Self.maxZoom)
                    }
                    .help("Zoom out")
                    Divider().frame(height: 18).overlay(Theme.separator)
                    Button { resetView() } label: {
                        Text("\(Int((zoom * liveZoom) * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 50, height: 28)
                    }
                    .buttonStyle(.plain).help("Reset view")
                    Divider().frame(height: 18).overlay(Theme.separator)
                    zoomButton(systemImage: "plus") {
                        zoom = (zoom + 0.2).clamped(to: Self.minZoom...Self.maxZoom)
                    }
                    .help("Zoom in")
                    Divider().frame(height: 18).overlay(Theme.separator)
                    zoomButton(systemImage: "viewfinder") { fitToContent() }
                        .help("Fit to content")
                }
                .background(Theme.cardBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
                .padding(12)
            }
        }
    }

    private func zoomButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private func resetView() {
        withAnimation(.easeInOut(duration: 0.2)) {
            cumulativePan = .zero
            pan = .zero
            zoom = 1.0
            liveZoom = 1.0
        }
    }

    /// Center the canvas on the bounding box of all step positions.
    private func fitToContent() {
        guard let doc = studio.document, !doc.steps.isEmpty else { resetView(); return }
        let positions = doc.steps.enumerated().map { idx, step in
            step.position ?? FlowDocument.autoLayoutPosition(forIndex: idx)
        }
        let minX = positions.map(\.x).min() ?? 0
        let maxX = (positions.map(\.x).max() ?? 0) + Double(Self.nodeWidth)
        let minY = positions.map(\.y).min() ?? 0
        let maxY = (positions.map(\.y).max() ?? 0) + Double(Self.nodeHeight)
        let contentW = maxX - minX
        let contentH = maxY - minY
        guard contentW > 0, contentH > 0 else { return }
        // Pad and target ~80% of an assumed viewport size; the real geo isn't
        // available here, so use a reasonable default. Users can fine-tune.
        let viewportW: Double = 900
        let viewportH: Double = 600
        let padding: Double = 80
        let scale = min((viewportW - padding * 2) / contentW,
                        (viewportH - padding * 2) / contentH, 1.0)
        let newZoom = CGFloat(max(Double(Self.minZoom), min(scale, Double(Self.maxZoom))))
        let centeredOffsetX = padding - minX * Double(newZoom)
        let centeredOffsetY = padding - minY * Double(newZoom)
        withAnimation(.easeInOut(duration: 0.25)) {
            zoom = newZoom
            liveZoom = 1.0
            pan = .zero
            cumulativePan = CGSize(width: centeredOffsetX, height: centeredOffsetY)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private func inspector(stepId: String) -> some View {
        if let doc = Binding(unwrap: $studio.document),
           let idx = doc.wrappedValue.steps.firstIndex(where: { $0.id == stepId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Step \(idx + 1)").font(Theme.headline).foregroundStyle(Theme.primaryText)
                        Spacer()
                        Button { selectedStepId = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).foregroundStyle(Theme.mutedText)
                    }
                    Text(doc.wrappedValue.steps[idx].id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.mutedText)
                    Divider().overlay(Theme.separator)
                    inspectorField("Intent", binding: doc.steps[idx].intent, multiline: true, disabled: !editable)
                    inspectorOptionalField("App", value: doc.steps[idx].app, disabled: !editable)
                    Toggle(isOn: doc.steps[idx].inferred) {
                        Text("Inferred").font(Theme.caption).foregroundStyle(Theme.secondaryText)
                    }
                    .toggleStyle(.switch).controlSize(.small).disabled(!editable)
                    inspectorOptionalField("Notes", value: doc.steps[idx].notes, multiline: true, disabled: !editable)
                    Divider().overlay(Theme.separator)
                    inspectorEdges(for: stepId, doc: doc.wrappedValue)
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func inspectorField(_ label: String, binding: Binding<String>, multiline: Bool = false, disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(Theme.mutedText)
            if multiline {
                TextField(label, text: binding, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(2...8)
                    .font(Theme.body).foregroundStyle(Theme.primaryText)
                    .padding(8).background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                    .disabled(disabled)
            } else {
                TextField(label, text: binding)
                    .textFieldStyle(.plain)
                    .font(Theme.body).foregroundStyle(Theme.primaryText)
                    .padding(8).background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                    .disabled(disabled)
            }
        }
    }

    private func inspectorOptionalField(_ label: String, value: Binding<String?>, multiline: Bool = false, disabled: Bool) -> some View {
        let proxy = Binding<String>(
            get: { value.wrappedValue ?? "" },
            set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
        return inspectorField(label, binding: proxy, multiline: multiline, disabled: disabled)
    }

    private func inspectorEdges(for stepId: String, doc: FlowDocument) -> some View {
        let outgoing = doc.edges().filter { $0.fromId == stepId }
        let step = doc.steps.first(where: { $0.id == stepId })
        let isLinearDefaultSuppressed = (step?.explicitNext?.isEmpty == true)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Connections").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                Spacer()
                if editable {
                    Button(connectingFrom == stepId ? "Cancel" : "Add") {
                        connectingFrom = (connectingFrom == stepId) ? nil : stepId
                    }
                    .buttonStyle(.plain).font(Theme.caption).foregroundStyle(Theme.accent)
                }
            }
            if outgoing.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isLinearDefaultSuppressed
                         ? "Linear default suppressed — no outgoing connection."
                         : "This step has no outgoing connection (end of flow).")
                        .font(Theme.caption).foregroundStyle(Theme.mutedText)
                    if isLinearDefaultSuppressed && editable {
                        Button("Restore default connection") {
                            studio.restoreLinearDefault(for: stepId)
                        }
                        .buttonStyle(.plain).font(Theme.caption).foregroundStyle(Theme.accent)
                    }
                }
            } else {
                ForEach(outgoing, id: \.self) { edge in
                    HStack(spacing: 6) {
                        Image(systemName: edge.isImplicit ? "arrow.right.circle" : "arrow.right.circle.fill")
                            .foregroundStyle(edge.isImplicit ? Theme.mutedText : Theme.accent)
                        Text("→ \(edge.toId)").font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.primaryText)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if editable {
                            Button { pendingDeleteEdge = edge } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).foregroundStyle(Theme.mutedText)
                                .help(edge.isImplicit ? "Cut the linear flow at this step" : "Remove this branch")
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }
}

// MARK: - N8N-style node card

private struct N8NNodeCard: View {
    let step: FlowDocument.Step
    let index: Int
    let selected: Bool
    let isConnectSource: Bool
    let connecting: Bool
    let editable: Bool
    let onSelect: () -> Void
    let onInputPortTap: () -> Void
    let onOutputPortTap: () -> Void
    /// Output-port drag callbacks. Location is in the `"worldLayer"` named
    /// coordinate space — i.e. world coords before the canvas's pan/zoom.
    let onOutputDragChanged: ((CGPoint) -> Void)?
    let onOutputDragEnded: ((CGPoint) -> Void)?
    let nodeWidth: CGFloat
    let nodeHeight: CGFloat
    let portRadius: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            cardBody
            inputPort.position(x: 0, y: nodeHeight / 2)
            outputPortView.position(x: nodeWidth, y: nodeHeight / 2)
        }
        .frame(width: nodeWidth, height: nodeHeight)
        .shadow(color: .black.opacity(selected ? 0.45 : 0.3), radius: selected ? 10 : 5, x: 0, y: 3)
    }

    private var cardBody: some View {
        HStack(alignment: .top, spacing: 10) {
            stepBadge
            VStack(alignment: .leading, spacing: 4) {
                titleRow
                Text(step.intent.isEmpty ? "(no intent)" : step.intent)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: nodeWidth, height: nodeHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 28/255, green: 30/255, blue: 36/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: selected || isConnectSource ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { onSelect() }
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text("Step \(index + 1)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            if let app = step.app, !app.isEmpty {
                Text("·").font(.caption).foregroundStyle(Theme.mutedText)
                Text(app).font(.caption).foregroundStyle(Theme.mutedText)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if step.inferred {
                Text("inferred").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.paused)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().stroke(Theme.paused.opacity(0.5)))
            }
        }
    }

    private var stepBadge: some View {
        Image(systemName: stepIcon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 6))
    }

    /// Pick an SF Symbol roughly matching the step's app, with a default.
    private var stepIcon: String {
        let app = step.app?.lowercased() ?? ""
        if app.contains("chatgpt") || app.contains("claude") || app.contains("atlas") { return "sparkles" }
        if app.contains("safari")  || app.contains("chrome") || app.contains("firefox") { return "globe" }
        if app.contains("terminal") || app.contains("iterm") { return "terminal" }
        if app.contains("code") || app.contains("xcode") || app.contains("codex") { return "chevron.left.forwardslash.chevron.right" }
        if app.contains("finder") { return "folder" }
        if app.contains("slack") || app.contains("mail") { return "bubble.left.and.bubble.right" }
        return "circle.grid.cross"
    }

    private var borderColor: Color {
        if isConnectSource { return Theme.accent }
        if connecting      { return Theme.accent.opacity(0.55) }
        if selected        { return Theme.accent.opacity(0.85) }
        return Color(red: 50/255, green: 53/255, blue: 60/255)
    }

    private var inputPort: some View {
        Circle()
            .fill(Color(red: 22/255, green: 24/255, blue: 28/255))
            .frame(width: portRadius * 2, height: portRadius * 2)
            .overlay(Circle().stroke(connecting ? Theme.accent : Color(red: 90/255, green: 95/255, blue: 105/255),
                                     lineWidth: connecting ? 2 : 1.5))
            .scaleEffect(connecting ? 1.3 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: connecting)
            .onTapGesture { onInputPortTap() }
            .help("Input — drop a connection here")
    }

    @ViewBuilder
    private var outputPortView: some View {
        let dot = Circle()
            .fill(isConnectSource ? Theme.accent : Color(red: 22/255, green: 24/255, blue: 28/255))
            .frame(width: portRadius * 2, height: portRadius * 2)
            .overlay(Circle().stroke(Theme.accent.opacity(isConnectSource ? 1 : 0.7), lineWidth: 1.5))
            .scaleEffect(isConnectSource ? 1.3 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isConnectSource)
            .onTapGesture { onOutputPortTap() }
            .help("Output — drag to another node's input to connect, or tap to start a connection")
        if editable, let onChanged = onOutputDragChanged, let onEnded = onOutputDragEnded {
            dot.highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("worldLayer"))
                    .onChanged { v in onChanged(v.location) }
                    .onEnded { v in onEnded(v.location) }
            )
        } else {
            dot
        }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        max(limits.lowerBound, min(limits.upperBound, self))
    }
}

// `Binding(unwrap:)` lives in StudioPane.swift (same module) — reused here.

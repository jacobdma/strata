import SwiftUI
import PencilKit

final class CanvasDrawingDelegate: NSObject, PKCanvasViewDelegate {
    var changed: ((PKDrawing) -> Void)?

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        changed?(canvasView.drawing)
    }
}

final class InkCanvas: PKCanvasView {
    private let history = UndoManager()
    // PKCanvasView forwards scroll callbacks; making it its own delegate can recurse.
    let drawingDelegate = CanvasDrawingDelegate()
    override var undoManager: UndoManager? { history }

    convenience init(ink: PKDrawing) {
        self.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        drawingPolicy = .anyInput
        isScrollEnabled = false
        contentInsetAdjustmentBehavior = .never
        tool = PKInkingTool(.pen, color: .black, width: 2)
        drawing = ink
        delegate = drawingDelegate
    }
}

@Observable
final class CanvasSession {
    var revision = 0
    @ObservationIgnored private var canvases: [UUID: InkCanvas] = [:]

    func canvas(for layer: DrawingLayer, drawingID: UUID, store: WorkspaceStore) -> InkCanvas {
        if let existing = canvases[layer.id] { return existing }
        let ink: PKDrawing
        do {
            ink = layer.ink.isEmpty ? PKDrawing() : try PKDrawing(data: layer.ink)
        } catch {
            let message = error.localizedDescription
            Task { store.blockEditing(message) }
            return InkCanvas(ink: PKDrawing())
        }
        let canvas = InkCanvas(ink: ink)
        let layerID = layer.id
        canvas.drawingDelegate.changed = { [weak self, weak store] drawing in
            let data = drawing.dataRepresentation()
            // Defer observable changes until UIKit has finished its current update.
            Task { @MainActor [weak self, weak store] in
                store?.updateInk(data, drawingID: drawingID, layerID: layerID)
                self?.revision += 1
            }
        }
        canvases[layer.id] = canvas
        return canvas
    }

    func canUndo(_ layer: DrawingLayer) -> Bool {
        _ = revision
        return canvases[layer.id]?.undoManager?.canUndo ?? false
    }

    func canRedo(_ layer: DrawingLayer) -> Bool {
        _ = revision
        return canvases[layer.id]?.undoManager?.canRedo ?? false
    }

    func undo(_ layer: DrawingLayer) { canvases[layer.id]?.undoManager?.undo(); revision += 1 }
    func redo(_ layer: DrawingLayer) { canvases[layer.id]?.undoManager?.redo(); revision += 1 }
}

struct DrawingSurface: View {
    let store: WorkspaceStore
    let session: CanvasSession
    let showGrid: Bool

    var body: some View {
        ZStack {
            Color.paper
            if showGrid {
                Canvas { context, size in
                    var dots = Path()
                    for x in stride(from: 24.0, to: size.width, by: 24) {
                        for y in stride(from: 24.0, to: size.height, by: 24) {
                            dots.addEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                        }
                    }
                    context.fill(dots, with: .color(.black.opacity(0.14)))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            CanvasBridge(drawing: store.drawing, store: store, session: session)
        }
        .clipped()
    }
}

final class LayeredCanvasView: UIView {
    private var layerIDs: [UUID] = []
    private var canvases: [InkCanvas] = []

    func display(_ drawing: Drawing, session: CanvasSession, store: WorkspaceStore) {
        let ids = drawing.layers.map(\.id)
        if ids != layerIDs {
            canvases.forEach { $0.removeFromSuperview() }
            canvases = drawing.layers.map { session.canvas(for: $0, drawingID: drawing.id, store: store) }
            canvases.forEach {
                $0.frame = bounds
                $0.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                addSubview($0)
            }
            layerIDs = ids
        }
        for (index, canvas) in canvases.enumerated() {
            let active = index == drawing.selectedLayer
            canvas.alpha = drawing.opacity(at: index)
            canvas.isUserInteractionEnabled = active
            canvas.accessibilityElementsHidden = !active
            canvas.accessibilityLabel = "Drawing canvas, \(drawing.layers[index].name)"
            canvas.accessibilityIdentifier = active ? "activeDrawingCanvas" : "inactiveDrawingCanvas"
        }
    }
}

private struct CanvasBridge: UIViewRepresentable {
    let drawing: Drawing
    let store: WorkspaceStore
    let session: CanvasSession

    func makeUIView(context: Context) -> LayeredCanvasView { LayeredCanvasView() }
    func updateUIView(_ uiView: LayeredCanvasView, context: Context) {
        uiView.display(drawing, session: session, store: store)
    }
}

import Foundation
import PencilKit
import UIKit
import Testing
@testable import Strata

@MainActor
struct CanvasRegressionTests {
    @Test func drawingDelegateIsSeparateAndForwardsChanges() {
        let canvas = InkCanvas(ink: PKDrawing())
        #expect((canvas.delegate as AnyObject?) !== canvas)
        #expect(canvas.delegate === canvas.drawingDelegate)
        var callbacks = 0
        canvas.drawingDelegate.changed = { _ in callbacks += 1 }
        canvas.drawingDelegate.canvasViewDrawingDidChange(canvas)
        #expect(callbacks == 1)
        // UIKit queries optional scroll-view delegate methods during layout.
        _ = canvas.delegate?.responds(to: #selector(UIScrollViewDelegate.scrollViewDidScroll(_:)))
        canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        canvas.layoutIfNeeded()
    }

    @Test func canvasHitTestingFollowsLayerSelection() {
        let store = WorkspaceStore(url: URL.temporaryDirectory.appending(path: UUID().uuidString))
        let session = CanvasSession()
        let view = LayeredCanvasView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        var drawing = store.drawing
        for selected in drawing.layers.indices {
            drawing.selectedLayer = selected
            view.display(drawing, session: session, store: store)
            view.layoutIfNeeded()
            let canvases = view.subviews.compactMap { $0 as? InkCanvas }
            #expect(canvases.count == drawing.layers.count)
            #expect(canvases.filter(\.isUserInteractionEnabled).count == 1)
            let active = canvases[selected]
            #expect(active.alpha == 1)
            #expect(active.drawingPolicy == .anyInput)
            let hit = view.hitTest(CGPoint(x: 100, y: 100), with: nil)
            #expect(hit === active || hit?.isDescendant(of: active) == true)
        }
    }

    @Test func switchingLayersRetainsCanvasAndUndoHistory() {
        let store = WorkspaceStore(url: URL.temporaryDirectory.appending(path: UUID().uuidString))
        let session = CanvasSession()
        let view = LayeredCanvasView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        var drawing = store.drawing
        view.display(drawing, session: session, store: store)
        let original = view.subviews.compactMap { $0 as? InkCanvas }
        var undone = false
        original[0].undoManager?.registerUndo(withTarget: original[0]) { _ in undone = true }
        drawing.selectedLayer = 0
        view.display(drawing, session: session, store: store)
        #expect(view.subviews[0] === original[0])
        session.undo(drawing.layers[0])
        #expect(undone)
        #expect(!session.canUndo(drawing.layers[1]))
    }
}

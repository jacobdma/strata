import Foundation
import Testing
@testable import Strata

@MainActor
struct StrataTests {
    private func temporaryURL() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "Workspace.strata")
    }

    @Test func layersFadeBelowSelectionAndSoloDoesNotChangeInk() {
        var drawing = Drawing(name: "Section")
        drawing.layers = (1...7).map { DrawingLayer(name: "Layer \($0)", ink: Data([$0])) }
        drawing.selectedLayer = 5
        #expect(drawing.opacity(at: 5) == 1)
        #expect(drawing.opacity(at: 4) == 0.55)
        #expect(drawing.opacity(at: 0) == 0.15)
        #expect(drawing.opacity(at: 6) == 0)
        let ink = drawing.layers.map(\.ink)
        drawing.solo = true
        #expect(drawing.layers.indices.filter { drawing.opacity(at: $0) > 0 } == [5])
        #expect(drawing.layers.map(\.ink) == ink)
    }

    @Test func savesAndRestoresHierarchySelectionAndInk() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorkspaceStore(url: url)
        store.addFolder()
        let folder = try #require(store.archive.folders.last)
        store.rename(folder.id, to: "  Studio  ")
        store.addProject(in: folder.id)
        store.rename(store.project.id, to: "Courtyard house")
        store.addDrawing()
        store.rename(store.drawing.id, to: "Elevation")
        store.addLayer()
        store.drawing.solo = true
        let layerID = try #require(store.drawing.layers.last?.id)
        store.updateInk(Data([1, 2, 3]), drawingID: store.drawing.id, layerID: layerID)
        store.save()
        #expect(store.storageError == nil)
        let restored = WorkspaceStore(url: url)
        #expect(restored.archive.folders.last?.name == "Studio")
        #expect(restored.project.name == "Courtyard house")
        #expect(restored.project.drawings.count == 2)
        #expect(restored.drawing.name == "Elevation")
        #expect(restored.drawing.layers.last?.ink == Data([1, 2, 3]))
        #expect(restored.drawing.selectedLayer == 3)
        #expect(restored.drawing.solo)
    }

    @Test func delayedInkUpdateBelongsToOriginalDrawing() {
        let store = WorkspaceStore(url: temporaryURL())
        let original = store.drawing
        let firstProject = store.project.id
        store.addProject(in: store.archive.folders[0].id)
        let nextDrawing = store.drawing.id
        store.updateInk(Data([42]), drawingID: original.id, layerID: original.layers[0].id)
        #expect(store.drawing.id == nextDrawing)
        #expect(store.drawing.layers[0].ink.isEmpty)
        store.openProject(firstProject)
        #expect(store.drawing.layers[0].ink == Data([42]))
        store.rename(original.id, to: " \n ")
        #expect(store.drawing.name == original.name)
    }

    @Test func corruptArchiveIsNeverOverwritten() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("incomplete archive".utf8)
        try original.write(to: url)
        let store = WorkspaceStore(url: url)
        #expect(store.loadFailed)
        #expect(store.storageError != nil)
        store.addDrawing()
        store.save()
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func invalidLayerSelectionIsRejected() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var archive = WorkspaceArchive()
        archive.folders[0].projects[0].drawings[0].selectedLayer = 50
        try JSONEncoder().encode(archive).write(to: url)
        #expect(WorkspaceStore(url: url).loadFailed)
    }

    @Test func editsAutosaveAfterDebounce() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorkspaceStore(url: url)
        store.rename(store.drawing.id, to: "Saved automatically")
        try await Task.sleep(for: .milliseconds(700))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(WorkspaceStore(url: url).drawing.name == "Saved automatically")
    }

    @Test func writeFailureIsReported() throws {
        let url = temporaryURL()
        let parent = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: parent) }
        try Data([0]).write(to: parent)
        let store = WorkspaceStore(url: url)
        store.save()
        #expect(store.storageError != nil)
    }
}

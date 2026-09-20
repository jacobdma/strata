import Foundation
import Observation

struct DrawingLayer: Codable, Identifiable {
    var id = UUID()
    var name: String
    var ink = Data()
}

struct Drawing: Codable, Identifiable {
    var id = UUID()
    var name: String
    var layers = (1...3).map { DrawingLayer(name: "Layer \($0)") }
    var selectedLayer = 1
    var solo = false

    func opacity(at index: Int) -> Double {
        guard index <= selectedLayer, !solo || index == selectedLayer else { return 0 }
        return index == selectedLayer ? 1 : max(0.15, pow(0.55, Double(selectedLayer - index)))
    }
}

struct Project: Codable, Identifiable {
    var id = UUID()
    var name: String
    var drawings = [Drawing(name: "Ground floor")]
}

struct ProjectFolder: Codable, Identifiable {
    var id = UUID()
    var name: String
    var projects: [Project] = []
}

struct WorkspaceArchive: Codable {
    var version = 1
    var folders = [ProjectFolder(name: "My projects", projects: [Project(name: "Untitled project")])]
    var projectID: UUID?
    var drawingID: UUID?

    var isValid: Bool {
        version == 1 && !folders.isEmpty && folders.contains { !$0.projects.isEmpty } &&
        folders.allSatisfy { folder in
            folder.projects.allSatisfy { project in
                !project.drawings.isEmpty && project.drawings.allSatisfy {
                    !$0.layers.isEmpty && $0.layers.indices.contains($0.selectedLayer)
                }
            }
        }
    }
}

@MainActor @Observable
final class WorkspaceStore {
    var archive = WorkspaceArchive() { didSet { scheduleSave() } }
    var storageError: String?
    private(set) var loadFailed = false
    private let url: URL
    private var pendingSave: Task<Void, Never>?

    init(url: URL = URL.documentsDirectory.appending(path: "Workspace.strata")) {
        self.url = url
        load()
    }

    private var location: (folder: Int, project: Int, drawing: Int) {
        for (f, folder) in archive.folders.enumerated() {
            if let p = folder.projects.firstIndex(where: { $0.id == archive.projectID }) {
                let d = folder.projects[p].drawings.firstIndex { $0.id == archive.drawingID } ?? 0
                return (f, p, d)
            }
        }
        return (archive.folders.firstIndex { !$0.projects.isEmpty } ?? 0, 0, 0)
    }

    var project: Project {
        get { archive.folders[location.folder].projects[location.project] }
        set { archive.folders[location.folder].projects[location.project] = newValue }
    }

    var drawing: Drawing {
        get { project.drawings[location.drawing] }
        set {
            let position = location
            archive.folders[position.folder].projects[position.project].drawings[position.drawing] = newValue
        }
    }

    func openProject(_ id: UUID) {
        archive.projectID = id
        archive.drawingID = project.drawings[0].id
    }

    func addFolder() {
        archive.folders.append(ProjectFolder(name: "New folder"))
    }

    func addProject(in folderID: UUID) {
        guard let index = archive.folders.firstIndex(where: { $0.id == folderID }) else { return }
        let newProject = Project(name: "Untitled project")
        archive.folders[index].projects.append(newProject)
        openProject(newProject.id)
    }

    func addDrawing() {
        let newDrawing = Drawing(name: "Drawing \(project.drawings.count + 1)")
        project.drawings.append(newDrawing)
        archive.drawingID = newDrawing.id
    }

    func addLayer() {
        drawing.layers.append(DrawingLayer(name: "Layer \(drawing.layers.count + 1)"))
        drawing.selectedLayer = drawing.layers.count - 1
    }

    func rename(_ id: UUID, to proposedName: String) {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        for f in archive.folders.indices {
            if archive.folders[f].id == id { archive.folders[f].name = name; return }
            for p in archive.folders[f].projects.indices {
                if archive.folders[f].projects[p].id == id { archive.folders[f].projects[p].name = name; return }
                for d in archive.folders[f].projects[p].drawings.indices {
                    if archive.folders[f].projects[p].drawings[d].id == id {
                        archive.folders[f].projects[p].drawings[d].name = name
                        return
                    }
                }
            }
        }
    }

    func updateInk(_ data: Data, drawingID: UUID, layerID: UUID) {
        for f in archive.folders.indices {
            for p in archive.folders[f].projects.indices {
                guard let d = archive.folders[f].projects[p].drawings.firstIndex(where: { $0.id == drawingID }),
                      let l = archive.folders[f].projects[p].drawings[d].layers.firstIndex(where: { $0.id == layerID })
                else { continue }
                archive.folders[f].projects[p].drawings[d].layers[l].ink = data
                return
            }
        }
    }

    func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let saved = try JSONDecoder().decode(WorkspaceArchive.self, from: Data(contentsOf: url))
            guard saved.isValid else { throw CocoaError(.fileReadCorruptFile) }
            loadFailed = false
            archive = saved
            storageError = nil
        } catch {
            loadFailed = true
            storageError = "Your saved workspace couldn’t be opened. The original file has been left untouched. \(error.localizedDescription)"
        }
    }

    func save() {
        pendingSave?.cancel()
        guard !loadFailed else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(archive).write(to: url, options: .atomic)
            storageError = nil
        } catch {
            storageError = "Changes couldn’t be saved. Please try again. \(error.localizedDescription)"
        }
    }

    func blockEditing(_ message: String) {
        loadFailed = true
        storageError = "A drawing couldn’t be opened. Your saved workspace has been left untouched. \(message)"
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.save()
        }
    }
}

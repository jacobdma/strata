import SwiftUI

struct RenameRequest: Identifiable {
    let id: UUID
    let name: String
}

struct RenameSheet: View {
    let request: RenameRequest
    let store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name).focused($focused)
                    .submitLabel(.done)
                    .onSubmit { commit() }
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commit() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(220)])
        .onAppear { name = request.name; focused = true }
    }

    private func commit() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.rename(request.id, to: name)
        dismiss()
    }
}

struct WorkspaceSidebar: View {
    let store: WorkspaceStore
    let selected: () -> Void
    @State private var expanded: Set<UUID> = []
    @State private var rename: RenameRequest?
    @State private var settings = false

    var body: some View {
        List {
            ForEach(store.archive.folders) { folder in
                DisclosureGroup(isExpanded: Binding(
                    get: { expanded.contains(folder.id) },
                    set: { if $0 { expanded.insert(folder.id) } else { expanded.remove(folder.id) } }
                )) {
                    ForEach(folder.projects) { project in
                        Button {
                            store.openProject(project.id)
                            selected()
                        } label: {
                            Label(project.name, systemImage: "square.stack")
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        }
                        .listRowBackground(project.id == store.project.id ? Color.sage.opacity(0.1) : .clear)
                        .accessibilityAddTraits(project.id == store.project.id ? .isSelected : [])
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                rename = RenameRequest(id: project.id, name: project.name)
                            }
                        }
                    }
                    Button("New project", systemImage: "plus") {
                        store.addProject(in: folder.id)
                        rename = RenameRequest(id: store.project.id, name: store.project.name)
                    }
                } label: {
                    Label(folder.name, systemImage: "folder")
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                rename = RenameRequest(id: folder.id, name: folder.name)
                            }
                            Button("New project", systemImage: "plus") {
                                store.addProject(in: folder.id)
                                expanded.insert(folder.id)
                            }
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("Strata")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { settings = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New folder", systemImage: "folder.badge.plus") {
                    store.addFolder()
                    if let folder = store.archive.folders.last {
                        expanded.insert(folder.id)
                        rename = RenameRequest(id: folder.id, name: folder.name)
                    }
                }
            }
        }
        .sheet(item: $rename) { RenameSheet(request: $0, store: store) }
        .sheet(isPresented: $settings) { WorkspaceSettings() }
        .onAppear { expanded.formUnion(store.archive.folders.map(\.id)) }
    }
}

struct ProjectDrawings: View {
    let store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var rename: RenameRequest?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.project.drawings) { drawing in
                    HStack {
                        Button {
                            store.archive.drawingID = drawing.id
                            dismiss()
                        } label: {
                            HStack {
                                Label(drawing.name, systemImage: "doc")
                                Spacer()
                                if drawing.id == store.drawing.id {
                                    Image(systemName: "checkmark").foregroundStyle(Color.sage)
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(drawing.id == store.drawing.id ? .isSelected : [])
                        Menu {
                            Button("Rename", systemImage: "pencil") {
                                rename = RenameRequest(id: drawing.id, name: drawing.name)
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        .accessibilityLabel("Options for \(drawing.name)")
                    }
                }
                Button("New drawing", systemImage: "plus") {
                    store.addDrawing()
                    rename = RenameRequest(id: store.drawing.id, name: store.drawing.name)
                }
            }
            .navigationTitle(store.project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .sheet(item: $rename) { RenameSheet(request: $0, store: store) }
        .frame(idealWidth: 360, idealHeight: 420)
    }
}

struct WorkspaceSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("layerHaptics") private var haptics = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Canvas") { Toggle("Dot grid", isOn: $showGrid) }
                Section {
                    Toggle("Layer selection haptics", isOn: $haptics)
                } footer: {
                    Text("Feedback is available on supported devices and accessories.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

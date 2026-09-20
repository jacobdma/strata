import SwiftUI

struct ContentView: View {
    let store: WorkspaceStore
    @State private var session = CanvasSession()
    @State private var columns: NavigationSplitViewVisibility = .detailOnly
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var toolsExpanded = true
    @State private var drawingsOpen = false
    @State private var showStorageError = false
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("layerHaptics") private var haptics = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            WorkspaceSidebar(store: store) {
                columns = .detailOnly
                compactColumn = .detail
            }
                .disabled(store.loadFailed)
        } detail: {
            GeometryReader { geometry in
                DrawingSurface(store: store, session: session, showGrid: showGrid)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 2) {
                            ToolButton(title: "Show projects", icon: "sidebar.left") {
                                columns = columns == .detailOnly ? .all : .detailOnly
                                compactColumn = columns == .detailOnly ? .detail : .sidebar
                            }
                            .accessibilityIdentifier("projectsToggle")
                            ToolButton(title: "Drawings in \(store.project.name)", icon: "doc.on.doc") {
                                drawingsOpen = true
                            }
                            .accessibilityIdentifier("drawingsToggle")
                            .popover(isPresented: $drawingsOpen) { ProjectDrawings(store: store) }
                        }
                        .padding(5)
                        .modifier(FloatingSurface())
                        .padding(16)
                    }
                    .overlay(alignment: .top) {
                        DrawingTools(store: store, session: session, expanded: $toolsExpanded, showGrid: $showGrid)
                            .padding(.top, geometry.size.width < 520 ? 80 : 16)
                    }
                    .overlay(alignment: .trailing) {
                        LayerControls(store: store, haptics: haptics,
                                      maximumVisibleLayers: max(1, min(5, Int((geometry.size.height - 300) / 44))))
                            .padding(.trailing, 16)
                            .offset(y: geometry.size.width < 520 ? 50 : 0)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if store.storageError != nil {
                            Button { showStorageError = true } label: {
                                Label(store.loadFailed ? "Saved workspace unavailable" : "Changes are not saved",
                                      systemImage: "exclamationmark.triangle")
                                    .font(.caption).padding(12)
                                    .background(.regularMaterial, in: Capsule())
                            }
                            .padding()
                        }
                    }
                    .disabled(store.loadFailed)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.sage)
        .preferredColorScheme(.light)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: toolsExpanded)
        .onChange(of: scenePhase) { _, phase in if phase != .active { store.save() } }
        .onChange(of: store.storageError, initial: true) { _, error in showStorageError = error != nil }
        .alert("Workspace storage", isPresented: $showStorageError) {
            Button("Retry") { if store.loadFailed { store.load() } else { store.save() } }
            Button("Close", role: .cancel) {}
        } message: {
            Text(store.storageError ?? "")
        }
    }
}

#Preview { ContentView(store: WorkspaceStore(url: URL.temporaryDirectory.appending(path: "Strata-preview.strata"))) }

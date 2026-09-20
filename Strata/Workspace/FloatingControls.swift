import SwiftUI

extension Color {
    static let sage = Color(red: 0.24, green: 0.36, blue: 0.31)
    static let paper = Color(red: 0.98, green: 0.975, blue: 0.955)
}

struct FloatingSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    Capsule().fill(Color.paper)
                } else {
                    Capsule().fill(.regularMaterial)
                }
            }
            .overlay {
                Capsule().stroke(Color.sage.opacity(0.12), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
    }
}

struct ToolButton: View {
    let title: String
    let icon: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .background(selected ? Color.sage.opacity(0.1) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.sage)
        .accessibilityLabel(title)
        .help(title)
    }
}

struct DrawingTools: View {
    let store: WorkspaceStore
    let session: CanvasSession
    @Binding var expanded: Bool
    @Binding var showGrid: Bool
    private var activeLayer: DrawingLayer { store.drawing.layers[store.drawing.selectedLayer] }

    var body: some View {
        HStack(spacing: 2) {
            ToolButton(title: expanded ? "Pen, black, 2 points. Hide tools" : "Show drawing tools",
                       icon: "pencil.tip", selected: true) { expanded.toggle() }
                .accessibilityIdentifier("drawingToolsToggle")
            if expanded {
                Divider().frame(height: 20).padding(.horizontal, 4)
                ToolButton(title: "Undo", icon: "arrow.uturn.backward") { session.undo(activeLayer) }
                    .disabled(!session.canUndo(activeLayer))
                ToolButton(title: "Redo", icon: "arrow.uturn.forward") { session.redo(activeLayer) }
                    .disabled(!session.canRedo(activeLayer))
                ToolButton(title: "Dot grid", icon: "circle.grid.3x3", selected: showGrid) { showGrid.toggle() }
                    .accessibilityValue(showGrid ? "On" : "Off")
                    .accessibilityIdentifier("gridToggle")
                ToolButton(title: "Hide drawing tools", icon: "chevron.up") { expanded = false }
            }
        }
        .padding(5)
        .modifier(FloatingSurface())
    }
}

struct LayerControls: View {
    let store: WorkspaceStore
    let haptics: Bool
    let maximumVisibleLayers: Int
    @State private var expanded = false
    @State private var rename = false
    @State private var name = ""
    @State private var dragStart: Int?
    private var drawing: Drawing { store.drawing }

    var body: some View {
        VStack(spacing: 4) {
            ToolButton(title: expanded ? "Hide layers" : "Show layers", icon: "square.3.layers.3d",
                       selected: drawing.solo) { expanded.toggle() }
                .accessibilityValue("\(drawing.layers[drawing.selectedLayer].name)\(drawing.solo ? ", solo" : "")")
                .accessibilityIdentifier("layersToggle")
            if expanded {
                // A moving window keeps each pill's 44-point target, even in a large stack.
                VStack(spacing: 0) {
                    ForEach(visibleLayers.reversed(), id: \.self) { index in
                        Capsule()
                            .fill(Color.sage.opacity(index == drawing.selectedLayer ? 1 : 0.22))
                            .frame(width: index == drawing.selectedLayer ? 28 : 16, height: 6)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .gesture(TapGesture(count: 2).exclusively(before: TapGesture())
                                .onEnded { result in
                                    store.drawing.selectedLayer = index
                                    if case .first = result { store.drawing.solo.toggle() }
                                })
                            .accessibilityElement()
                            .accessibilityLabel(drawing.layers[index].name)
                            .accessibilityAddTraits(index == drawing.selectedLayer ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { store.drawing.selectedLayer = index }
                            .accessibilityIdentifier("layerDot\(index + 1)")
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        if dragStart == nil { dragStart = drawing.selectedLayer }
                        let steps = Int((-value.translation.height / 36).rounded())
                        store.drawing.selectedLayer = min(drawing.layers.count - 1, max(0, (dragStart ?? 0) + steps))
                    }
                    .onEnded { _ in dragStart = nil })
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 1 : -1
                    store.drawing.selectedLayer = min(drawing.layers.count - 1, max(0, drawing.selectedLayer + step))
                }
                Text("\(drawing.selectedLayer + 1)/\(drawing.layers.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                ToolButton(title: "Show current layer only", icon: drawing.solo ? "square.fill" : "square.on.square",
                           selected: drawing.solo) { store.drawing.solo.toggle() }
                    .accessibilityValue(drawing.solo ? "On" : "Off")
                ToolButton(title: "Add layer", icon: "plus") { store.addLayer() }
            }
        }
        .padding(5)
        .modifier(FloatingSurface())
        .overlay(alignment: .leading) {
            if expanded {
                Button {
                    name = drawing.layers[drawing.selectedLayer].name
                    rename = true
                } label: {
                    Text(drawing.layers[drawing.selectedLayer].name)
                        .font(.caption.weight(.medium)).lineLimit(1)
                        .padding(.horizontal, 12).frame(height: 44)
                }
                .buttonStyle(.plain)
                .modifier(FloatingSurface())
                .frame(width: 120)
                .offset(x: -132)
                .accessibilityLabel("Rename current layer")
            }
        }
        .sensoryFeedback(.selection, trigger: drawing.selectedLayer) { _, _ in haptics }
        .alert("Rename layer", isPresented: $rename) {
            TextField("Layer name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { store.drawing.layers[store.drawing.selectedLayer].name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var visibleLayers: Range<Int> {
        let start = min(max(0, drawing.selectedLayer - maximumVisibleLayers / 2),
                        max(0, drawing.layers.count - maximumVisibleLayers))
        return start..<min(drawing.layers.count, start + maximumVisibleLayers)
    }
}

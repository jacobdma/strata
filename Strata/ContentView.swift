import SwiftUI
import PencilKit

@Observable
private final class Sketch: Identifiable {
    let id = UUID()
    let title: String
    var layers = (1...3).map { _ in DrawingLayer() }
    var selectedLayer = 1

    init(title: String) { self.title = title }
    var active: DrawingLayer { layers[selectedLayer] }
}

private final class InkCanvas: PKCanvasView {
    private let history = UndoManager()
    override var undoManager: UndoManager? { history }
}

private final class DrawingLayer: Identifiable {
    let id = UUID()
    let canvas = InkCanvas()

    init() {
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.isScrollEnabled = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 2)
    }
}

struct ContentView: View {
    @State private var sketches = [Sketch(title: "Ground floor")]
    @State private var selectedID: UUID?
    @State private var showGrid = true
    private let accent = Color(red: 0.24, green: 0.36, blue: 0.31)

    private var sketch: Sketch {
        sketches.first { $0.id == selectedID } ?? sketches[0]
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                Section("Drawings") {
                    ForEach(sketches) { item in
                        Label(item.title, systemImage: "doc")
                            .padding(.vertical, 6)
                            .tag(item.id)
                    }
                }
            }
            .navigationTitle("Strata")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            .safeAreaInset(edge: .bottom) {
                Button(action: addSketch) {
                    Label("New drawing", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .buttonStyle(.plain)
            }
        } detail: {
            VStack(spacing: 0) {
                drawingToolbar
                Divider()
                HStack(spacing: 16) {
                    ZStack {
                        Color.white
                        if showGrid { dotGrid }
                        ForEach(sketch.layers) { layer in
                            DrawingCanvas(layer: layer, active: layer.id == sketch.active.id)
                                .allowsHitTesting(layer.id == sketch.active.id)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.black.opacity(0.06)))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .accessibilityLabel("Drawing canvas")
                    layerRail
                }
                .padding(24)
                HStack {
                    Text("SKETCH / \(sketch.title.uppercased())")
                        .tracking(1.5)
                    Spacer()
                    Text("Apple Pencil or touch")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .background(Color(red: 0.95, green: 0.95, blue: 0.93))
            .navigationTitle(sketch.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(accent)
        .preferredColorScheme(.light)
        .onAppear { if selectedID == nil { selectedID = sketches[0].id } }
    }

    private var drawingToolbar: some View {
        HStack(spacing: 8) {
            Label("Pen", systemImage: "pencil.tip")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(accent.opacity(0.1), in: Capsule())
            Circle().fill(.black).frame(width: 10, height: 10).padding(.leading, 8)
            Text("2 pt").font(.caption).foregroundStyle(.secondary)
            Spacer()
            tool("Undo", icon: "arrow.uturn.backward") { sketch.active.canvas.undoManager?.undo() }
            tool("Redo", icon: "arrow.uturn.forward") { sketch.active.canvas.undoManager?.redo() }
            Divider().frame(height: 20).padding(.horizontal, 8)
            tool("Toggle grid", icon: showGrid ? "circle.grid.3x3.fill" : "circle.grid.3x3") {
                showGrid.toggle()
            }
            .accessibilityValue(showGrid ? "On" : "Off")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.white.opacity(0.8))
    }

    private var layerRail: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.3.layers.3d")
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text("LAYERS").font(.system(size: 9, weight: .semibold)).tracking(1)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(sketch.layers.indices.reversed(), id: \.self) { index in
                    Button { sketch.selectedLayer = index } label: {
                        Capsule()
                            .fill(index == sketch.selectedLayer ? accent : accent.opacity(0.2))
                            .frame(width: index == sketch.selectedLayer ? 28 : 16, height: 6)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Layer \(index + 1)")
                    .accessibilityAddTraits(index == sketch.selectedLayer ? .isSelected : [])
                }
            }
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.1)))
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let row = min(sketch.layers.count - 1, max(0, Int(value.location.y / 44)))
                sketch.selectedLayer = sketch.layers.count - 1 - row
            })
            .accessibilityHint("Slide vertically to switch layers")
            Text(String(format: "%02d", sketch.selectedLayer + 1))
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(accent)
            tool("Add layer", icon: "plus") {
                sketch.layers.append(DrawingLayer())
                sketch.selectedLayer = sketch.layers.count - 1
            }
            .disabled(sketch.layers.count >= 8)
            .help("Add a layer (up to 8 per drawing)")
        }
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .animation(.easeOut(duration: 0.12), value: sketch.selectedLayer)
    }

    private var dotGrid: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: 24.0, to: size.width, by: 24) {
                for y in stride(from: 24.0, to: size.height, by: 24) {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            context.fill(dots, with: .color(.black.opacity(0.15)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tool(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

    private func addSketch() {
        let newSketch = Sketch(title: "Drawing \(sketches.count + 1)")
        sketches.append(newSketch)
        selectedID = newSketch.id
    }
}

private struct DrawingCanvas: UIViewRepresentable {
    let layer: DrawingLayer
    let active: Bool

    func makeUIView(context: Context) -> PKCanvasView { layer.canvas }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.isUserInteractionEnabled = active
    }
}

#Preview { ContentView() }

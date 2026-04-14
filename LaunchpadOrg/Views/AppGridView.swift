import SwiftUI
import UniformTypeIdentifiers

struct AppGridView: View {
    @Environment(LayoutStore.self) private var store
    @Environment(DragState.self) private var drag
    let pageIndex: Int
    @Binding var selectedAppID: UUID?
    var onOpenFolder: (AppFolder) -> Void
    var onCreateFolder: (AppFolder) -> Void

    /// Preferred icon slot width. The grid picks an integer number of columns
    /// that fits the available width closest to this.
    private let preferredSlotWidth: CGFloat = 130
    /// Column count is clamped to this range regardless of window size.
    private let minCols = 4
    private let maxCols = 10

    var body: some View {
        GeometryReader { geo in
            let cols = columnCount(for: geo.size.width)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: cols)
            let nodes = store.pages.indices.contains(pageIndex) ? store.pages[pageIndex] : []

            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    let here = IndexPath(item: index, section: pageIndex)
                    nodeView(node, at: here)
                        .opacity(drag.source == here ? 0.3 : 1)
                        .scaleEffect(drag.hoverTarget == here && drag.source != here ? 1.08 : 1)
                        .animation(.easeOut(duration: 0.15), value: drag.hoverTarget)
                        .animation(.easeOut(duration: 0.15), value: drag.source)
                        .onDrag {
                            drag.source = here
                            // Payload is ignored — DragState is the source of truth — but
                            // SwiftUI requires a non-empty NSItemProvider to start a drag.
                            return NSItemProvider(object: "x" as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: FastDropDelegate(
                                store: store,
                                drag: drag,
                                target: here,
                                onCreateFolder: onCreateFolder
                            )
                        )
                }
            }
            .padding(.horizontal, max(24, (geo.size.width - CGFloat(cols) * preferredSlotWidth) / 2))
            .padding(.vertical, 24)
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        let raw = Int((width - 48) / preferredSlotWidth)
        return min(max(raw, minCols), maxCols)
    }

    @ViewBuilder
    private func nodeView(_ node: LayoutNode, at index: IndexPath) -> some View {
        switch node {
        case .app(let id):
            if let app = store.app(for: id) {
                AppIconView(item: app, selectedAppID: $selectedAppID)
            }
        case .folder(let folder):
            FolderIconView(
                folder: folder,
                apps: store.apps(in: folder),
                isDropTarget: drag.hoverTarget == index && drag.source != index
            )
            .onTapGesture(count: 2) { onOpenFolder(folder) }
            .onTapGesture(count: 1) { selectedAppID = nil }
        }
    }
}

/// Drop delegate that reads the drag source directly from `DragState` instead
/// of decoding an NSItemProvider payload. Saves the async round-trip that
/// made the old drop feel laggy, and lets `dropEntered`/`dropExited` update
/// a live hover-target highlight.
struct FastDropDelegate: DropDelegate {
    let store: LayoutStore
    let drag: DragState
    let target: IndexPath
    let onCreateFolder: (AppFolder) -> Void

    func dropEntered(info: DropInfo) {
        drag.hoverTarget = target
    }

    func dropExited(info: DropInfo) {
        if drag.hoverTarget == target { drag.hoverTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { drag.clear() }
        guard let source = drag.source, source != target else { return false }
        let newFolder = store.dropOnto(source: source, target: target)
        if let newFolder {
            // Give the layout one runloop tick to settle before opening the sheet.
            DispatchQueue.main.async { onCreateFolder(newFolder) }
        }
        return true
    }
}

struct SearchResultsGrid: View {
    let results: [AppItem]
    @Binding var selectedAppID: UUID?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 7)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(results) { app in
                    AppIconView(item: app, selectedAppID: $selectedAppID)
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 24)
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct AppGridView: View {
    @Environment(LayoutStore.self) private var store
    @Environment(DragState.self) private var drag

    /// Pre-sliced page contents. ContentView computes the live-reflow
    /// preview from the store and passes in the relevant page's slice.
    let nodes: [LayoutNode]
    /// Flat-index of the first item on this page in `store.flatNodes`.
    /// Each slot's flat index is `baseFlatIndex + localIndex` — BUT during
    /// a drag the UI is rendering a *virtual* order, so the flat index we
    /// report for drop targets is the item's index in the real store (not
    /// its visual position). See `realIndex(of:)` below.
    let baseFlatIndex: Int
    let cols: Int
    let rows: Int
    let iconSize: CGFloat
    @Binding var selectedAppID: UUID?
    var onOpenFolder: (AppFolder) -> Void
    var onCreateFolder: (AppFolder) -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: cols)
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(nodes, id: \.id) { node in
                let real = store.flatNodes.firstIndex { $0.id == node.id } ?? 0
                slotView(node: node, realIndex: real)
                    .frame(height: iconSize + 28)
                    .opacity(drag.source == real ? 0.22 : 1)
                    .scaleEffect(scaleFor(real))
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: nodes.map(\.id))
                    .animation(.easeOut(duration: 0.15), value: drag.hoverTarget)
                    .animation(.easeOut(duration: 0.2), value: drag.willCreateFolder)
                    .onDrop(
                        of: [UTType.text],
                        delegate: FastDropDelegate(
                            store: store,
                            drag: drag,
                            targetRealIndex: real,
                            onCreateFolder: onCreateFolder
                        )
                    )
            }
        }
    }

    private func scaleFor(_ real: Int) -> CGFloat {
        guard drag.hoverTarget == real, drag.source != real else { return 1 }
        return drag.willCreateFolder ? 1.12 : 1.04
    }

    @ViewBuilder
    private func slotView(node: LayoutNode, realIndex: Int) -> some View {
        switch node {
        case .app(let id):
            if let app = store.app(for: id) {
                AppIconView(item: app,
                            iconSize: iconSize,
                            selectedAppID: $selectedAppID)
                    .onDrag {
                        drag.source = realIndex
                        return NSItemProvider(object: "grid:\(realIndex)" as NSString)
                    }
            }
        case .folder(let folder):
            FolderIconView(
                folder: folder,
                apps: store.apps(in: folder),
                iconSize: iconSize,
                isDropTarget: drag.hoverTarget == realIndex && drag.source != realIndex
            )
            .onTapGesture { onOpenFolder(folder) }
            .onDrag {
                drag.source = realIndex
                return NSItemProvider(object: "grid:\(realIndex)" as NSString)
            }
        }
    }
}

/// Drop delegate — records hover target for live-reflow preview, arms the
/// dwell timer for folder creation, and commits a move or merge on release.
struct FastDropDelegate: DropDelegate {
    let store: LayoutStore
    let drag: DragState
    let targetRealIndex: Int
    let onCreateFolder: (AppFolder) -> Void

    func dropEntered(info: DropInfo) {
        drag.hoverTarget = targetRealIndex
        drag.willCreateFolder = false
        drag.scheduleDwell(0.5) {
            drag.willCreateFolder = true
        }
    }

    func dropExited(info: DropInfo) {
        if drag.hoverTarget == targetRealIndex {
            drag.hoverTarget = nil
            drag.willCreateFolder = false
            drag.cancelDwell()
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let source = drag.source
        let wantsFolder = drag.willCreateFolder
        defer { drag.clear() }
        guard let source, source != targetRealIndex,
              store.flatNodes.indices.contains(targetRealIndex) else {
            return false
        }

        let targetNode = store.flatNodes[targetRealIndex]
        switch targetNode {
        case .folder:
            store.mergeOnto(source: source, target: targetRealIndex)
        case .app where wantsFolder:
            if let newFolder = store.mergeOnto(source: source, target: targetRealIndex) {
                DispatchQueue.main.async { onCreateFolder(newFolder) }
            }
        case .app:
            // Live-reflow already previewed this via the UI's virtual order;
            // commit the actual shift now.
            store.move(from: source, to: targetRealIndex)
        }
        return true
    }
}

struct SearchResultsGrid: View {
    let results: [AppItem]
    @Binding var selectedAppID: UUID?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 7)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(results) { app in
                    AppIconView(item: app, selectedAppID: $selectedAppID)
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 20)
        }
    }
}

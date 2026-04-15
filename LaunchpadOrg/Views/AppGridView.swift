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
    /// its visual position).
    let baseFlatIndex: Int
    /// Precomputed id → real flat index, built once per render by the parent
    /// so each slot doesn't have to scan `store.flatNodes` itself.
    let idToRealIndex: [UUID: Int]
    let cols: Int
    let rows: Int
    let iconSize: CGFloat
    let slotWidth: CGFloat
    @Binding var selectedAppID: UUID?
    var onOpenFolder: (AppFolder) -> Void
    var onCreateFolder: (AppFolder) -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: cols)
        // Hoist the identity fingerprint outside the ForEach — otherwise
        // every slot recomputes the full id list, which is O(n²) per render.
        let identityKey = nodes.map(\.id)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(nodes, id: \.id) { node in
                let real = idToRealIndex[node.id] ?? 0
                slotView(node: node, realIndex: real)
                    .frame(height: iconSize + 28)
                    .opacity(drag.source == real ? 0.22 : 1)
                    .scaleEffect(scaleFor(real))
                    .onDrop(
                        of: [UTType.text],
                        delegate: FastDropDelegate(
                            store: store,
                            drag: drag,
                            targetRealIndex: real,
                            cellWidth: slotWidth,
                            onCreateFolder: onCreateFolder
                        )
                    )
            }
        }
        // Animate reflow + hover highlights at the grid level so there's one
        // animation driver per page rather than one per cell.
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: identityKey)
        .animation(.easeOut(duration: 0.15), value: drag.hoverTarget)
        .animation(.easeOut(duration: 0.2), value: drag.willCreateFolder)
        // Short / incomplete pages should hug the top-left rather than
        // centering the grid in the page frame.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func scaleFor(_ real: Int) -> CGFloat {
        guard drag.hoverTarget == real, drag.source != real else { return 1 }
        // Merge zone = folder cue → pop the target larger.
        return drag.willCreateFolder ? 1.12 : 1.0
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

/// Drop delegate — classifies the pointer position inside the hovered cell
/// into one of three zones (insert-before / merge / insert-after) and drives
/// the preview + commit from that. No dwell timer: hovering the icon center
/// is itself the "create folder" signal.
struct FastDropDelegate: DropDelegate {
    let store: LayoutStore
    let drag: DragState
    let targetRealIndex: Int
    let cellWidth: CGFloat
    let onCreateFolder: (AppFolder) -> Void

    private func zone(for info: DropInfo) -> DropZone {
        // DropInfo.location is cell-local (origin at top-left of the target).
        // Split the cell horizontally into thirds.
        let w = max(cellWidth, 1)
        let x = info.location.x
        if x < w * 0.33 { return .insertBefore }
        if x > w * 0.67 { return .insertAfter }
        return .merge
    }

    func dropEntered(info: DropInfo) {
        drag.hoverTarget = targetRealIndex
        updateZone(info: info)
    }

    func dropExited(info: DropInfo) {
        if drag.hoverTarget == targetRealIndex {
            drag.hoverTarget = nil
            drag.willCreateFolder = false
            drag.dropZone = .merge
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if drag.hoverTarget != targetRealIndex {
            drag.hoverTarget = targetRealIndex
        }
        updateZone(info: info)
        return DropProposal(operation: .move)
    }

    private func updateZone(info: DropInfo) {
        let z = zone(for: info)
        // Only write when the value actually changes — Observation fires a
        // re-render on every mutation, and `dropUpdated` runs on every
        // mouse-move tick. Guarding here keeps the frame rate up.
        if drag.dropZone != z { drag.dropZone = z }
        let differentSlot = drag.source != targetRealIndex
        let willFolder = (z == .merge) && differentSlot
        if drag.willCreateFolder != willFolder { drag.willCreateFolder = willFolder }
    }

    func performDrop(info: DropInfo) -> Bool {
        let source = drag.source
        let z = drag.dropZone
        defer { drag.clear() }
        guard let source,
              store.flatNodes.indices.contains(targetRealIndex) else {
            return false
        }

        // Merge zone → folder create / add to folder.
        if z == .merge {
            guard source != targetRealIndex else { return false }
            let targetNode = store.flatNodes[targetRealIndex]
            switch targetNode {
            case .folder:
                store.mergeOnto(source: source, target: targetRealIndex)
            case .app:
                if let newFolder = store.mergeOnto(source: source, target: targetRealIndex) {
                    DispatchQueue.main.async { onCreateFolder(newFolder) }
                }
            }
            return true
        }

        // Insert-between: compute the landing slot and reorder.
        var insertAt = targetRealIndex + (z == .insertAfter ? 1 : 0)
        // `move(from:to:)` removes first, so adjust when moving rightward.
        if source < insertAt { insertAt -= 1 }
        insertAt = min(max(insertAt, 0), store.flatNodes.count - 1)
        if insertAt != source {
            store.move(from: source, to: insertAt)
        }
        return true
    }
}

struct SearchResultsGrid: View {
    let results: [AppItem]
    let highlightedIndex: Int
    @Binding var selectedAppID: UUID?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 7)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Array(results.enumerated()), id: \.element.id) { idx, app in
                    AppIconView(item: app, selectedAppID: .constant(
                        idx == highlightedIndex ? app.id : selectedAppID
                    ))
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 20)
        }
    }
}

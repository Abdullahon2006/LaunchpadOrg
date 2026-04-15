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
    let cols: Int
    let rows: Int
    let iconSize: CGFloat
    let slotWidth: CGFloat
    @Binding var selectedAppID: UUID?
    var onOpenFolder: (AppFolder) -> Void
    var onCreateFolder: (AppFolder) -> Void

    var body: some View {
        // Build id → real flat index once per page render.
        let idToRealIndex = Self.buildIndexMap(store.flatNodes)
        // Hoist the identity fingerprint outside the ForEach so the
        // reflow animation has a single driver per page.
        let identityKey = nodes.map(\.id)
        // Manual row-by-row layout. LazyVGrid's flex-column distribution
        // was collapsing rows past the first couple to a narrower width
        // in some window sizes; a plain VStack-of-HStacks is deterministic
        // and pins the cell size to exactly `slotWidth` regardless of
        // how SwiftUI negotiates proposals upstream.
        let rowSpacing: CGFloat = 18
        let colSpacing: CGFloat = 12
        let gridWidth = CGFloat(cols) * slotWidth + CGFloat(max(cols - 1, 0)) * colSpacing
        // Build the row layout as a concrete nested array — `[RowModel]`
        // where each row already carries its own `[CellModel]` with cols
        // entries (real nodes padded with nils). This avoids ForEach-over-
        // index-range pitfalls during fullscreen-transition size flux, where
        // cols and nodes.count were sometimes out of phase across passes.
        let rows = Self.buildRows(nodes: nodes, cols: cols)
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(rows) { row in
                HStack(spacing: colSpacing) {
                    ForEach(row.cells) { cell in
                        cellView(cell: cell, idToRealIndex: idToRealIndex)
                            .frame(width: slotWidth, height: iconSize + 28)
                    }
                }
                .frame(width: gridWidth, alignment: .leading)
            }
        }
        // Pin the VStack to the exact grid width and left-align it within
        // any larger parent — prevents SwiftUI from squeezing cols in a
        // narrow proposal and lets a partial last row hug the left edge.
        .frame(width: gridWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Animate reflow + hover highlights at the grid level so there's one
        // animation driver per page rather than one per cell.
        .animation(.interpolatingSpring(stiffness: 420, damping: 34), value: identityKey)
        .animation(.easeOut(duration: 0.12), value: drag.hoverTarget)
        .animation(.easeOut(duration: 0.15), value: drag.willCreateFolder)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func cellView(cell: CellModel, idToRealIndex: [UUID: Int]) -> some View {
        if let node = cell.node {
            let real = idToRealIndex[node.id] ?? 0
            slotView(node: node, realIndex: real)
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
        } else {
            // Empty trailing cells on a partial last row — take up the slot
            // so the row doesn't stretch to fill the page width.
            Color.clear
        }
    }

    /// One cell slot — carries either a real node or nil (padding on the
    /// last partial row). The stable `id` combines row+col so SwiftUI
    /// treats each slot as its own identity and can't recycle a row's
    /// cells across renders with mismatched cols.
    struct CellModel: Identifiable {
        let id: String
        let node: LayoutNode?
    }

    struct RowModel: Identifiable {
        let id: Int
        let cells: [CellModel]
    }

    private static func buildRows(nodes: [LayoutNode], cols: Int) -> [RowModel] {
        let c = max(cols, 1)
        let rowCount = max(Int(ceil(Double(nodes.count) / Double(c))), nodes.isEmpty ? 0 : 1)
        var rows: [RowModel] = []
        rows.reserveCapacity(rowCount)
        for r in 0 ..< rowCount {
            var cells: [CellModel] = []
            cells.reserveCapacity(c)
            for col in 0 ..< c {
                let i = r * c + col
                let node: LayoutNode? = (i < nodes.count) ? nodes[i] : nil
                cells.append(CellModel(id: "\(r)-\(col)", node: node))
            }
            rows.append(RowModel(id: r, cells: cells))
        }
        return rows
    }

    private static func buildIndexMap(_ flat: [LayoutNode]) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        map.reserveCapacity(flat.count)
        for (i, node) in flat.enumerated() { map[node.id] = i }
        return map
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

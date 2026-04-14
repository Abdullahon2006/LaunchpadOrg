import SwiftUI
import UniformTypeIdentifiers

struct AppGridView: View {
    @Environment(LayoutStore.self) private var store
    @Environment(DragState.self) private var drag
    let pageIndex: Int
    /// Paginated grid geometry, supplied by ContentView so the store's page
    /// size and the visible layout stay in sync with window width.
    let cols: Int
    let rows: Int
    let slotWidth: CGFloat
    let iconSize: CGFloat
    @Binding var selectedAppID: UUID?
    var onOpenFolder: (AppFolder) -> Void
    var onCreateFolder: (AppFolder) -> Void

    var body: some View {
        let nodes = store.pages.indices.contains(pageIndex) ? store.pages[pageIndex] : []
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: cols)
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(0 ..< max(nodes.count, cols * rows), id: \.self) { index in
                let flat = store.flatIndex(page: pageIndex, item: index)
                let node = index < nodes.count ? nodes[index] : nil
                slotView(node: node, at: flat, index: index)
                    .frame(height: iconSize + 28)
                    .opacity(drag.source == flat ? 0.25 : 1)
                    .scaleEffect(scaleFor(flat, isEmpty: node == nil))
                    .animation(.easeOut(duration: 0.15), value: drag.hoverTarget)
                    .animation(.easeOut(duration: 0.15), value: drag.source)
                    .animation(.easeOut(duration: 0.2), value: drag.willCreateFolder)
                    .onDrop(
                        of: [UTType.text],
                        delegate: FastDropDelegate(
                            store: store,
                            drag: drag,
                            target: flat,
                            targetIsEmpty: node == nil,
                            onCreateFolder: onCreateFolder
                        )
                    )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func scaleFor(_ flat: Int, isEmpty: Bool) -> CGFloat {
        guard drag.hoverTarget == flat, drag.source != flat else { return 1 }
        if isEmpty { return 1 }
        return drag.willCreateFolder ? 1.12 : 1.05
    }

    @ViewBuilder
    private func slotView(node: LayoutNode?, at flat: Int, index: Int) -> some View {
        switch node {
        case .app(let id)?:
            if let app = store.app(for: id) {
                AppIconView(item: app,
                            iconSize: iconSize,
                            selectedAppID: $selectedAppID)
                    .onDrag {
                        drag.source = flat
                        return NSItemProvider(object: "grid:\(flat)" as NSString)
                    }
            }
        case .folder(let folder)?:
            FolderIconView(
                folder: folder,
                apps: store.apps(in: folder),
                iconSize: iconSize,
                isDropTarget: drag.hoverTarget == flat && drag.source != flat
            )
            .onTapGesture { onOpenFolder(folder) }
            .onDrag {
                drag.source = flat
                return NSItemProvider(object: "grid:\(flat)" as NSString)
            }
        case nil:
            // Empty slot — invisible, but must be a real frame so it's
            // droppable and occupies a grid cell. No drag handler.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
    }
}

/// Drop delegate — all drop logic goes through `DragState`, so reads of the
/// source happen synchronously in `performDrop`.
struct FastDropDelegate: DropDelegate {
    let store: LayoutStore
    let drag: DragState
    let target: Int
    let targetIsEmpty: Bool
    let onCreateFolder: (AppFolder) -> Void

    func dropEntered(info: DropInfo) {
        drag.hoverTarget = target
        drag.willCreateFolder = false
        // Only arm folder-create on non-empty targets — you can't merge
        // an app with empty space.
        guard !targetIsEmpty else { return }
        drag.scheduleDwell(0.5) {
            drag.willCreateFolder = true
        }
    }

    func dropExited(info: DropInfo) {
        if drag.hoverTarget == target {
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
        guard let source, source != target else { return false }

        // Need to know what's *at* the target in the live store.
        let (page, item) = (target / store.pageSize, target % store.pageSize)
        let targetNode: LayoutNode? = {
            guard store.pages.indices.contains(page),
                  store.pages[page].indices.contains(item) else { return nil }
            return store.pages[page][item]
        }()

        switch targetNode {
        case .folder?:
            store.mergeOnto(source: source, target: target)
        case .app? where wantsFolder:
            if let newFolder = store.mergeOnto(source: source, target: target) {
                DispatchQueue.main.async { onCreateFolder(newFolder) }
            }
        case .app?, nil:
            // Default: swap slots. Empty-slot drop = "move to empty".
            store.swap(from: source, to: target)
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

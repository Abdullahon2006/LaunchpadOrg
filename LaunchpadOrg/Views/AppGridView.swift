import SwiftUI
import UniformTypeIdentifiers

struct AppGridView: View {
    @Environment(LayoutStore.self) private var store
    @Environment(DragState.self) private var drag
    let pageIndex: Int
    @Binding var selectedAppID: UUID?
    var onOpenFolder: (AppFolder) -> Void
    var onCreateFolder: (AppFolder) -> Void

    /// Preferred icon slot width. The grid picks a column count that fits
    /// the available window width closest to this value.
    private let preferredSlotWidth: CGFloat = 130
    private let minCols = 5
    private let maxCols = 12
    private let sidePadding: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            let cols = columnCount(for: geo.size.width)
            let usable = max(0, geo.size.width - sidePadding * 2)
            let slot = usable / CGFloat(cols)
            // Icon size grows with the slot so fullscreen actually uses the
            // extra space instead of leaving huge margins.
            let iconSize = min(120, max(64, slot - 42))
            let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: cols)
            let nodes = store.pages.indices.contains(pageIndex) ? store.pages[pageIndex] : []

            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    let here = IndexPath(item: index, section: pageIndex)
                    nodeView(node, at: here, iconSize: iconSize)
                        .opacity(drag.source == here ? 0.3 : 1)
                        .scaleEffect(scaleFor(here))
                        .animation(.easeOut(duration: 0.15), value: drag.hoverTarget)
                        .animation(.easeOut(duration: 0.15), value: drag.source)
                        .animation(.easeOut(duration: 0.2), value: drag.willCreateFolder)
                        .onDrag {
                            drag.source = here
                            // Payload is ignored on the receiving side — DragState
                            // is the source of truth — but SwiftUI requires a
                            // non-empty provider to start a drag session.
                            return NSItemProvider(object: "grid:\(here.section):\(here.item)" as NSString)
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
            .padding(.horizontal, sidePadding)
            .padding(.vertical, 20)
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        let raw = Int((width - sidePadding * 2) / preferredSlotWidth)
        return min(max(raw, minCols), maxCols)
    }

    private func scaleFor(_ here: IndexPath) -> CGFloat {
        guard drag.hoverTarget == here, drag.source != here else { return 1 }
        return drag.willCreateFolder ? 1.12 : 1.04
    }

    @ViewBuilder
    private func nodeView(_ node: LayoutNode, at index: IndexPath, iconSize: CGFloat) -> some View {
        switch node {
        case .app(let id):
            if let app = store.app(for: id) {
                AppIconView(item: app,
                            iconSize: iconSize,
                            selectedAppID: $selectedAppID)
            }
        case .folder(let folder):
            FolderIconView(
                folder: folder,
                apps: store.apps(in: folder),
                iconSize: iconSize,
                isDropTarget: drag.hoverTarget == index && drag.source != index
            )
            .onTapGesture { onOpenFolder(folder) } // single click opens folder
        }
    }
}

/// Drop delegate driven by `DragState`.
///
/// Behavior matrix at drop time:
///  • target is a folder             → add source app to that folder
///  • target is an app, dwell ≥0.5s  → create a new folder around the two
///  • target is an app otherwise     → reorder (source takes target slot)
struct FastDropDelegate: DropDelegate {
    let store: LayoutStore
    let drag: DragState
    let target: IndexPath
    let onCreateFolder: (AppFolder) -> Void

    func dropEntered(info: DropInfo) {
        drag.hoverTarget = target
        drag.willCreateFolder = false
        // Promote to folder-create mode if the user lingers on the same icon.
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
        let willCreateFolder = drag.willCreateFolder
        defer { drag.clear() }

        guard let source,
              source != target,
              store.pages.indices.contains(target.section),
              store.pages[target.section].indices.contains(target.item) else {
            return false
        }

        let targetNode = store.pages[target.section][target.item]

        switch targetNode {
        case .folder:
            store.dropOnto(source: source, target: target)
        case .app:
            if willCreateFolder {
                let newFolder = store.dropOnto(source: source, target: target)
                if let newFolder {
                    DispatchQueue.main.async { onCreateFolder(newFolder) }
                }
            } else {
                store.move(from: source, to: target)
            }
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
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(results) { app in
                    AppIconView(item: app, selectedAppID: $selectedAppID)
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 20)
        }
    }
}

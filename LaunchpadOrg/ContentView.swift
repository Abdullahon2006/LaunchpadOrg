import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(LayoutStore.self) private var store
    @Environment(DragState.self) private var drag
    @State private var query: String = ""
    @State private var selectedPage: Int = 0
    @State private var dragOffsetX: CGFloat = 0
    @State private var openFolder: AppFolder?
    @State private var newlyCreatedFolderID: UUID?
    @State private var selectedAppID: UUID?

    // Grid sizing constants.
    private let preferredSlotWidth: CGFloat = 128
    private let preferredSlotHeight: CGFloat = 120
    private let minCols = 5
    private let maxCols = 12
    private let minRows = 3
    private let maxRows = 7
    private let sidePadding: CGFloat = 48
    private let topChromeHeight: CGFloat = 76 // search bar + its padding

    var body: some View {
        GeometryReader { geo in
            let (cols, rows) = gridDims(in: geo.size)
            let usable = max(0, geo.size.width - sidePadding * 2)
            let slot = usable / CGFloat(cols)
            let iconSize = min(128, max(60, slot - 38))
            let pageSize = cols * rows

            ZStack {
                background

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        SearchBar(text: $query)
                            .padding(.top, 22)
                        Spacer()
                    }
                    .frame(height: topChromeHeight)

                    if query.isEmpty {
                        pager(width: geo.size.width,
                              cols: cols,
                              rows: rows,
                              slot: slot,
                              iconSize: iconSize)
                    } else {
                        SearchResultsGrid(
                            results: store.search(query),
                            selectedAppID: $selectedAppID
                        )
                    }
                }
                .padding(.horizontal, sidePadding)

                if let folder = openFolder, let latest = currentFolder(id: folder.id) {
                    folderOverlay(folder: latest)
                }
            }
            .onAppear {
                store.pageSize = pageSize
                installGestures(pageWidth: geo.size.width)
            }
            .onChange(of: pageSize) { _, newValue in
                store.pageSize = newValue
                // Clamp selected page if we collapsed pages.
                if selectedPage >= store.pages.count {
                    selectedPage = max(0, store.pages.count - 1)
                }
            }
            .onChange(of: geo.size.width) { _, _ in
                installGestures(pageWidth: geo.size.width)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: openFolder?.id)
        }
        .onTapGesture { selectedAppID = nil }
    }

    // MARK: Background

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.08, green: 0.09, blue: 0.16),
                     Color(red: 0.14, green: 0.10, blue: 0.22)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: Pager — finger-following

    private func pager(width: CGFloat, cols: Int, rows: Int, slot: CGFloat, iconSize: CGFloat) -> some View {
        let pageCount = max(store.pages.count, 1)
        let clamped = min(max(selectedPage, 0), pageCount - 1)
        let pageW = width - sidePadding * 2
        return HStack(spacing: 0) {
            ForEach(0 ..< pageCount, id: \.self) { idx in
                AppGridView(
                    pageIndex: idx,
                    cols: cols,
                    rows: rows,
                    slotWidth: slot,
                    iconSize: iconSize,
                    selectedAppID: $selectedAppID,
                    onOpenFolder: { folder in
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            openFolder = folder
                        }
                    },
                    onCreateFolder: { folder in
                        newlyCreatedFolderID = folder.id
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            openFolder = folder
                        }
                    }
                )
                .frame(width: pageW)
            }
        }
        .frame(width: pageW, alignment: .leading)
        .offset(x: -CGFloat(clamped) * pageW + dragOffsetX)
        // No implicit animation on dragOffsetX — it tracks the finger in real
        // time. Only the *end-of-gesture snap* is animated (below).
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.88), value: clamped)
        .clipped()
    }

    // MARK: Folder overlay

    @ViewBuilder
    private func folderOverlay(folder: AppFolder) -> some View {
        Color.black.opacity(0.55)
            .ignoresSafeArea()
            .onTapGesture { closeFolder() }
            // Drop an in-folder drag anywhere on the backdrop → remove that
            // app from the folder. The panel itself doesn't accept drops, so
            // releases inside the panel fall through here too; the drop
            // delegate no-ops unless the user was actually dragging an app
            // out of the folder (drag.draggingOutOfFolder != nil).
            .onDrop(
                of: [UTType.text],
                delegate: RemoveFromFolderDropDelegate(
                    drag: drag,
                    store: store,
                    folderID: folder.id,
                    onDidRemove: {
                        // If the folder emptied out, close the panel.
                        if currentFolder(id: folder.id) == nil {
                            closeFolder()
                        }
                    }
                )
            )
            .transition(.opacity)

        FolderDetailView(
            folder: folder,
            apps: store.apps(in: folder),
            selectedAppID: $selectedAppID,
            autoFocusName: folder.id == newlyCreatedFolderID,
            onRename: { newName in
                store.renameFolder(id: folder.id, to: newName)
            },
            onClose: closeFolder
        )
        .transition(.scale(scale: 0.88).combined(with: .opacity))
    }

    private func closeFolder() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            openFolder = nil
            newlyCreatedFolderID = nil
        }
    }

    private func currentFolder(id: UUID) -> AppFolder? {
        for page in store.pages {
            for node in page {
                if case .folder(let f)? = node, f.id == id { return f }
            }
        }
        return nil
    }

    // MARK: Grid sizing

    private func gridDims(in size: CGSize) -> (Int, Int) {
        let usableW = max(0, size.width - sidePadding * 2)
        let usableH = max(0, size.height - topChromeHeight - 32)
        let cols = min(max(Int(usableW / preferredSlotWidth), minCols), maxCols)
        let rows = min(max(Int(usableH / preferredSlotHeight), minRows), maxRows)
        return (cols, rows)
    }

    // MARK: Gestures — finger-following swipe

    private func installGestures(pageWidth: CGFloat) {
        GestureMonitor.shared.install()

        let pageW = max(1, pageWidth - sidePadding * 2)

        GestureMonitor.shared.onScrollDelta = { dx in
            // While dragging the pager, the dragOffsetX follows the finger
            // 1:1. Clamp to ±one page so an over-fast flick doesn't skip
            // multiple pages.
            guard query.isEmpty, openFolder == nil else { return }
            let next = dragOffsetX + dx
            dragOffsetX = min(max(next, -pageW), pageW)
        }

        GestureMonitor.shared.onScrollEnd = { _ in
            guard query.isEmpty, openFolder == nil else { return }
            let pageCount = max(store.pages.count, 1)
            var newPage = selectedPage
            let threshold = pageW / 4
            if dragOffsetX < -threshold, selectedPage < pageCount - 1 {
                newPage += 1
            } else if dragOffsetX > threshold, selectedPage > 0 {
                newPage -= 1
            }
            // The committed page change cancels out the drag offset: offset
            // goes from (dragOffsetX) to 0 while base page shifts. Animate
            // both together so the finger-follow motion continues smoothly
            // into the snap rather than jumping.
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
                selectedPage = newPage
                dragOffsetX = 0
            }
        }

        GestureMonitor.shared.onPinch = { magnification in
            guard let w = NSApp.keyWindow else { return }
            let isFull = w.styleMask.contains(.fullScreen)
            if magnification < -0.15, isFull {
                w.toggleFullScreen(nil)
            } else if magnification > 0.25, !isFull {
                w.toggleFullScreen(nil)
            }
        }
    }
}

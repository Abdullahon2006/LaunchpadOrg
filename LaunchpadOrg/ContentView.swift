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
    @State private var highlightedSearchIndex: Int = 0
    @FocusState private var searchFocused: Bool

    // Generous margins — icons shouldn't touch the window edges.
    private let horizontalMargin: CGFloat = 72
    private let topMargin: CGFloat = 18
    private let bottomMargin: CGFloat = 48

    // Grid sizing constants.
    private let preferredSlotWidth: CGFloat = 128
    private let preferredSlotHeight: CGFloat = 120
    private let minCols = 5
    private let maxCols = 12
    private let minRows = 3
    private let maxRows = 7
    private let searchBarHeight: CGFloat = 76

    var body: some View {
        GeometryReader { geo in
            let (cols, rows) = gridDims(in: geo.size)
            let usableW = max(0, geo.size.width - horizontalMargin * 2)
            let slot = usableW / CGFloat(cols)
            let iconSize = min(128, max(60, slot - 42))
            let pageSize = cols * rows
            // Live reflow preview: if a drag is in flight, reorder flatNodes
            // virtually so the UI shows other icons sliding to close the gap.
            let visualFlat = store.previewFlat(
                movingFrom: drag.source,
                to: drag.hoverTarget,
                zone: drag.dropZone
            )
            let searchResults = store.search(query)

            ZStack {
                background

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        SearchBar(text: $query, focused: $searchFocused)
                            .padding(.top, topMargin)
                        Spacer()
                    }
                    .frame(height: searchBarHeight)

                    if query.isEmpty {
                        pager(width: geo.size.width,
                              cols: cols,
                              rows: rows,
                              iconSize: iconSize,
                              slotWidth: slot,
                              pageSize: pageSize,
                              visualFlat: visualFlat)
                        .padding(.bottom, bottomMargin)
                    } else {
                        SearchResultsGrid(
                            results: searchResults,
                            highlightedIndex: min(highlightedSearchIndex, max(searchResults.count - 1, 0)),
                            selectedAppID: $selectedAppID
                        )
                    }
                }

                // Edge drag-advance strips: while a grid drag is in flight
                // and the pointer dwells on the left/right 48 pt of the
                // window, flip to the previous / next page so the user can
                // carry an icon across pages.
                if drag.source != nil && query.isEmpty && openFolder == nil {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: 48)
                            .contentShape(Rectangle())
                            .onDrop(of: [UTType.text],
                                    delegate: EdgePageFlipDropDelegate(
                                        drag: drag,
                                        advance: { flipPage(by: -1) }
                                    ))
                        Spacer()
                        Color.clear
                            .frame(width: 48)
                            .contentShape(Rectangle())
                            .onDrop(of: [UTType.text],
                                    delegate: EdgePageFlipDropDelegate(
                                        drag: drag,
                                        advance: { flipPage(by: 1) }
                                    ))
                    }
                    .allowsHitTesting(true)
                }

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
                if selectedPage >= store.pages.count {
                    selectedPage = max(0, store.pages.count - 1)
                }
            }
            .onChange(of: geo.size.width) { _, _ in
                installGestures(pageWidth: geo.size.width)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: openFolder?.id)
            .onChange(of: query) { _, newValue in
                highlightedSearchIndex = 0
                if !newValue.isEmpty { searchFocused = true }
            }
            .focusable()
            .onKeyPress(.escape) {
                if !query.isEmpty {
                    query = ""
                    searchFocused = false
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.return) {
                let results = store.search(query)
                guard !results.isEmpty else { return .ignored }
                let idx = min(max(highlightedSearchIndex, 0), results.count - 1)
                AppLauncher.launch(results[idx])
                return .handled
            }
            .onKeyPress(.leftArrow) { moveHighlight(-1) }
            .onKeyPress(.rightArrow) { moveHighlight(1) }
            .onKeyPress(.upArrow) { moveHighlight(-7) }
            .onKeyPress(.downArrow) { moveHighlight(7) }
            // Any printable keystroke anywhere in the window: funnel it into
            // the search field. Matches Spotlight / Launchpad behaviour.
            .onKeyPress(phases: .down) { press in
                guard openFolder == nil else { return .ignored }
                // Ignore control/command combos and non-character keys.
                if press.modifiers.contains(.command) || press.modifiers.contains(.control) {
                    return .ignored
                }
                let chars = press.characters
                guard chars.count == 1,
                      let scalar = chars.unicodeScalars.first,
                      CharacterSet.alphanumerics.contains(scalar) ||
                      CharacterSet.punctuationCharacters.contains(scalar) ||
                      scalar == " " else {
                    return .ignored
                }
                if !searchFocused {
                    query.append(chars)
                    searchFocused = true
                    return .handled
                }
                return .ignored
            }
        }
        .onTapGesture { selectedAppID = nil }
    }

    private func flipPage(by delta: Int) {
        let pageCount = max(store.pages.count, 1)
        let next = min(max(selectedPage + delta, 0), pageCount - 1)
        guard next != selectedPage else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            selectedPage = next
        }
    }

    private func moveHighlight(_ delta: Int) -> KeyPress.Result {
        let results = store.search(query)
        guard !results.isEmpty else { return .ignored }
        let next = min(max(highlightedSearchIndex + delta, 0), results.count - 1)
        highlightedSearchIndex = next
        selectedAppID = results[next].id
        return .handled
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

    // MARK: Pager

    private func pager(width: CGFloat,
                       cols: Int,
                       rows: Int,
                       iconSize: CGFloat,
                       slotWidth: CGFloat,
                       pageSize: Int,
                       visualFlat: [LayoutNode]) -> some View {
        // How many pages does the current virtual list occupy?
        let pageCount = max(Int(ceil(Double(visualFlat.count) / Double(max(pageSize, 1)))), 1)
        let clamped = min(max(selectedPage, 0), pageCount - 1)
        let pageW = max(1, width - horizontalMargin * 2)

        return HStack(spacing: 0) {
            ForEach(0 ..< pageCount, id: \.self) { idx in
                let start = idx * pageSize
                let end = min(start + pageSize, visualFlat.count)
                let slice = (start < end) ? Array(visualFlat[start ..< end]) : []
                AppGridView(
                    nodes: slice,
                    baseFlatIndex: start,
                    cols: cols,
                    rows: rows,
                    iconSize: iconSize,
                    slotWidth: slotWidth,
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
                .frame(width: pageW, alignment: .topLeading)
            }
        }
        .frame(width: pageW)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .offset(x: -CGFloat(clamped) * pageW + dragOffsetX)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: clamped)
        // Clip *inside* the margin so adjacent pages can't bleed into it
        // while swiping. Must come before the outer `.padding` so clipping
        // happens on the page-wide region, not the padded region.
        .frame(width: pageW)
        .clipped()
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalMargin)
    }

    // MARK: Folder overlay

    @ViewBuilder
    private func folderOverlay(folder: AppFolder) -> some View {
        Color.black.opacity(0.55)
            .ignoresSafeArea()
            .onTapGesture { closeFolder() }
            .onDrop(
                of: [UTType.text],
                delegate: RemoveFromFolderDropDelegate(
                    drag: drag,
                    store: store,
                    folderID: folder.id,
                    onDidRemove: {
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
        for node in store.flatNodes {
            if case .folder(let f) = node, f.id == id { return f }
        }
        return nil
    }

    // MARK: Grid sizing

    private func gridDims(in size: CGSize) -> (Int, Int) {
        let usableW = max(0, size.width - horizontalMargin * 2)
        let usableH = max(0, size.height - searchBarHeight - bottomMargin - 20)
        let cols = min(max(Int(usableW / preferredSlotWidth), minCols), maxCols)
        let rows = min(max(Int(usableH / preferredSlotHeight), minRows), maxRows)
        return (cols, rows)
    }

    // MARK: Gestures

    private func installGestures(pageWidth: CGFloat) {
        GestureMonitor.shared.install()
        let pageW = max(1, pageWidth - horizontalMargin * 2)

        GestureMonitor.shared.onScrollDelta = { dx in
            guard query.isEmpty, openFolder == nil else { return }
            let next = dragOffsetX + dx
            dragOffsetX = min(max(next, -pageW), pageW)
        }

        GestureMonitor.shared.onScrollEnd = { _ in
            guard query.isEmpty, openFolder == nil else { return }
            let pageCount = max(store.pages.count, 1)
            var newPage = selectedPage
            // Low threshold: a small, intentional swipe (~1/7 of the page
            // width) commits the flip. Paired with the snap spring below,
            // the feel is "let go and it decides" rather than "drag all
            // the way across".
            let threshold = pageW / 7
            if dragOffsetX < -threshold, selectedPage < pageCount - 1 {
                newPage += 1
            } else if dragOffsetX > threshold, selectedPage > 0 {
                newPage -= 1
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
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

/// Drop delegate for the left/right edge strips. While a drag hovers the
/// strip for ~0.4 s, it flips the pager to the neighbouring page. Lets the
/// user carry an icon across pages without first releasing it.
struct EdgePageFlipDropDelegate: DropDelegate {
    let drag: DragState
    let advance: () -> Void

    func dropEntered(info: DropInfo) {
        // Only arm when an actual grid drag is in progress.
        guard drag.source != nil else { return }
        drag.scheduleDwell(0.4) {
            advance()
            // Re-arm so continued hover keeps paging forward.
            drag.scheduleDwell(0.55) { advance() }
        }
    }

    func dropExited(info: DropInfo) {
        drag.cancelDwell()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        // Releasing on the edge strip itself is a no-op: the user should
        // aim at a real slot on the new page.
        drag.cancelDwell()
        return false
    }
}

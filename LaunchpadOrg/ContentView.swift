import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(LayoutStore.self) private var store
    @Environment(DragState.self) private var drag
    @State private var query: String = ""
    @State private var selectedPage: Int = 0
    @State private var openFolder: AppFolder?
    @State private var newlyCreatedFolderID: UUID?
    @State private var selectedAppID: UUID?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        SearchBar(text: $query)
                            .padding(.top, 22)
                        Spacer()
                    }

                    if query.isEmpty {
                        pagedGrid(width: geo.size.width)
                    } else {
                        SearchResultsGrid(
                            results: store.search(query),
                            selectedAppID: $selectedAppID
                        )
                    }

                    Spacer(minLength: 0)
                }

                // Folder overlay — replaces .sheet so we control the animation
                // and can dismiss with a tap on the backdrop.
                if let folder = openFolder,
                   let latest = currentFolder(id: folder.id) {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { commitCloseFolder() }
                        .transition(.opacity)

                    FolderDetailView(
                        folder: latest,
                        apps: store.apps(in: latest),
                        selectedAppID: $selectedAppID,
                        autoFocusName: latest.id == newlyCreatedFolderID,
                        onRename: { newName in
                            store.renameFolder(id: latest.id, to: newName)
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                openFolder = nil
                                newlyCreatedFolderID = nil
                            }
                        }
                    )
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: openFolder?.id)
        }
        .onAppear(perform: installGestures)
        .onTapGesture { selectedAppID = nil }
    }

    /// Look up the folder fresh from the store each render so the detail view
    /// reflects edits (rename, app-add, app-remove) without having to rebind.
    private func currentFolder(id: UUID) -> AppFolder? {
        for page in store.pages {
            for node in page {
                if case .folder(let f) = node, f.id == id { return f }
            }
        }
        return nil
    }

    private func commitCloseFolder() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            openFolder = nil
            newlyCreatedFolderID = nil
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.08, green: 0.09, blue: 0.16),
                     Color(red: 0.14, green: 0.10, blue: 0.22)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func pagedGrid(width: CGFloat) -> some View {
        let pageCount = max(store.pages.count, 1)
        let clamped = min(max(selectedPage, 0), pageCount - 1)
        return HStack(spacing: 0) {
            ForEach(store.pages.indices, id: \.self) { idx in
                AppGridView(
                    pageIndex: idx,
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
                .frame(width: width)
            }
        }
        .frame(width: width, alignment: .leading)
        .offset(x: -CGFloat(clamped) * width)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: clamped)
        .clipped()
    }

    private func installGestures() {
        GestureMonitor.shared.install()
        GestureMonitor.shared.onSwipePage = { direction in
            guard query.isEmpty, openFolder == nil else { return }
            let target = selectedPage + direction
            if store.pages.indices.contains(target) {
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                    selectedPage = target
                }
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

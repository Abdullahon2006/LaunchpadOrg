import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(LayoutStore.self) private var store
    @State private var query: String = ""
    @State private var selectedPage: Int = 0
    @State private var openFolder: AppFolder?
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
            }
        }
        .onAppear {
            GestureMonitor.shared.install()
            GestureMonitor.shared.onSwipePage = { direction in
                guard query.isEmpty else { return }
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
        .onTapGesture {
            // Click on empty background clears selection.
            selectedAppID = nil
        }
        .sheet(item: $openFolder) { folder in
            FolderDetailView(
                folder: folder,
                apps: store.apps(in: folder),
                selectedAppID: $selectedAppID,
                onRename: { newName in
                    store.renameFolder(id: folder.id, to: newName)
                },
                onClose: { openFolder = nil }
            )
            .environment(store)
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

    /// Custom offset-based pager. Lighter than TabView — only the active page's
    /// grid is in the live layout, and the slide animation is a single offset
    /// interpolation instead of TabView's full cross-fade.
    private func pagedGrid(width: CGFloat) -> some View {
        let pageCount = max(store.pages.count, 1)
        let clamped = min(max(selectedPage, 0), pageCount - 1)
        return HStack(spacing: 0) {
            ForEach(store.pages.indices, id: \.self) { idx in
                AppGridView(
                    pageIndex: idx,
                    selectedAppID: $selectedAppID,
                    onOpenFolder: { openFolder = $0 }
                )
                .frame(width: width)
            }
        }
        .frame(width: width, alignment: .leading)
        .offset(x: -CGFloat(clamped) * width)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: clamped)
        .clipped()
    }
}

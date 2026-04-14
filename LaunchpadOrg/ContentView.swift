import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(LayoutStore.self) private var store
    @State private var query: String = ""
    @State private var selectedPage: Int = 0
    @State private var openFolder: AppFolder?

    var body: some View {
        ZStack {
            background

            // Invisible overlay that captures trackpad scroll + pinch.
            TrackpadGestureView(
                onSwipePage: { direction in
                    guard query.isEmpty else { return }
                    let target = selectedPage + direction
                    if store.pages.indices.contains(target) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selectedPage = target
                        }
                    }
                },
                onPinch: { magnification in
                    // Pinch-in (negative) exits fullscreen — matches native Launchpad.
                    if magnification < -0.15 {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    } else if magnification > 0.25 {
                        // Pinch-out enters fullscreen if not already.
                        if let w = NSApp.keyWindow,
                           !w.styleMask.contains(.fullScreen) {
                            w.toggleFullScreen(nil)
                        }
                    }
                }
            )
            .allowsHitTesting(true)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    SearchBar(text: $query)
                        .padding(.top, 22)
                    Spacer()
                }

                if query.isEmpty {
                    pagedGrid
                } else {
                    SearchResultsGrid(results: store.search(query))
                }

                Spacer(minLength: 0)

                if query.isEmpty, store.pages.count > 1 {
                    pageIndicator
                        .padding(.bottom, 20)
                }
            }
        }
        .sheet(item: $openFolder) { folder in
            FolderDetailView(
                folder: folder,
                apps: store.apps(in: folder),
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

    private var pagedGrid: some View {
        TabView(selection: $selectedPage) {
            ForEach(Array(store.pages.enumerated()), id: \.offset) { idx, _ in
                AppGridView(pageIndex: idx) { folder in
                    openFolder = folder
                }
                .tag(idx)
            }
        }
        .tabViewStyle(.automatic)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(store.pages.indices, id: \.self) { i in
                Circle()
                    .fill(i == selectedPage ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .onTapGesture { selectedPage = i }
            }
        }
    }
}

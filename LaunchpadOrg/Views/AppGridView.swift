import SwiftUI
import UniformTypeIdentifiers

struct AppGridView: View {
    @Environment(LayoutStore.self) private var store
    let pageIndex: Int
    var onOpenFolder: (AppFolder) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 7)

    var body: some View {
        let nodes = store.pages.indices.contains(pageIndex) ? store.pages[pageIndex] : []
        LazyVGrid(columns: columns, spacing: 28) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                nodeView(node)
                    .onDrag {
                        NSItemProvider(object: "\(pageIndex):\(index)" as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: GridDropDelegate(
                            store: store,
                            target: IndexPath(item: index, section: pageIndex)
                        )
                    )
            }
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func nodeView(_ node: LayoutNode) -> some View {
        switch node {
        case .app(let id):
            if let app = store.app(for: id) {
                AppIconView(item: app)
            }
        case .folder(let folder):
            FolderIconView(folder: folder, apps: store.apps(in: folder))
                .onTapGesture { onOpenFolder(folder) }
        }
    }
}

struct GridDropDelegate: DropDelegate {
    let store: LayoutStore
    let target: IndexPath

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
            var string: String?
            if let d = data as? Data {
                string = String(data: d, encoding: .utf8)
            } else if let s = data as? String {
                string = s
            } else if let ns = data as? NSString {
                string = ns as String
            }
            guard let raw = string else { return }
            let parts = raw.split(separator: ":")
            guard parts.count == 2,
                  let page = Int(parts[0]),
                  let item = Int(parts[1]) else { return }
            let source = IndexPath(item: item, section: page)
            DispatchQueue.main.async {
                store.dropOnto(source: source, target: target)
            }
        }
        return true
    }
}

struct SearchResultsGrid: View {
    let results: [AppItem]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 7)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(results) { app in
                    AppIconView(item: app)
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 24)
        }
    }
}

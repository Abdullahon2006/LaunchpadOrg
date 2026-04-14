import Foundation
import Observation
import AppKit

/// Packed (no gaps) layout store.
///
///   • Single flat, ordered list of `LayoutNode` (no optional slots).
///   • The paginated view (`pages`) is a derived slicing of the flat list
///     by the current `pageSize`, which itself is driven by window geometry.
///   • All mutations use flat `Int` indices. `move(from:to:)` is remove +
///     insert — i.e., iOS-style shift/reflow. There's no sparse-swap.
@Observable
final class LayoutStore {
    private(set) var apps: [UUID: AppItem] = [:]

    /// Flattened ground-truth order. Everything else derives from this.
    private(set) var flatNodes: [LayoutNode] = []

    /// Derived paginated view. Recomputed when `flatNodes` or `pageSize` change.
    private(set) var pages: [[LayoutNode]] = []

    /// Cells-per-page. Set by ContentView from the window's geometry.
    var pageSize: Int = 35 {
        didSet { if oldValue != pageSize { repaginate() } }
    }

    @ObservationIgnored private var searchIndex: [(id: UUID, lowered: String)] = []
    @ObservationIgnored private var iconCache: [UUID: NSImage] = [:]

    private let defaultsKey = "LaunchpadOrg.layout.v3"

    init() {
        reload()
    }

    // MARK: Lookups

    func icon(for item: AppItem) -> NSImage {
        if let cached = iconCache[item.id] { return cached }
        let img = NSWorkspace.shared.icon(forFile: item.bundleURL.path)
        iconCache[item.id] = img
        return img
    }

    func app(for id: UUID) -> AppItem? { apps[id] }

    func apps(in folder: AppFolder) -> [AppItem] {
        folder.appIDs.compactMap { apps[$0] }
    }

    func search(_ query: String) -> [AppItem] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return searchIndex
            .filter { $0.lowered.contains(q) }
            .compactMap { apps[$0.id] }
    }

    // MARK: Pagination

    /// Convert flat index → (page, local) for navigation.
    func location(forFlat flat: Int) -> (page: Int, local: Int) {
        let size = max(pageSize, 1)
        return (flat / size, flat % size)
    }

    /// Convert (page, local) → flat index.
    func flatIndex(page: Int, item: Int) -> Int { page * pageSize + item }

    private func repaginate() {
        let size = max(pageSize, 1)
        var rebuilt: [[LayoutNode]] = []
        var i = 0
        while i < flatNodes.count {
            let end = min(i + size, flatNodes.count)
            rebuilt.append(Array(flatNodes[i ..< end]))
            i = end
        }
        if rebuilt.isEmpty { rebuilt = [[]] }
        pages = rebuilt
    }

    // MARK: Mutations

    /// Remove-and-insert (shift). Neighbors compact into the vacated slot.
    func move(from source: Int, to target: Int) {
        guard source != target,
              flatNodes.indices.contains(source) else { return }
        let t = min(max(target, 0), flatNodes.count - 1)
        let item = flatNodes.remove(at: source)
        flatNodes.insert(item, at: t)
        repaginate()
        save()
    }

    /// Merge the source app onto the target. Creates a new folder if the
    /// target is also an app; adds to the folder if the target already is
    /// one. The source slot is then removed (shifted out).
    @discardableResult
    func mergeOnto(source: Int, target: Int) -> AppFolder? {
        guard source != target,
              flatNodes.indices.contains(source),
              flatNodes.indices.contains(target),
              case .app(let srcID) = flatNodes[source] else { return nil }

        // Produce the new target content, then remove the source slot.
        var createdFolder: AppFolder?
        switch flatNodes[target] {
        case .folder(var folder):
            if !folder.appIDs.contains(srcID) { folder.appIDs.append(srcID) }
            flatNodes[target] = .folder(folder)
        case .app(let tgtID):
            let folder = AppFolder(name: "Untitled", appIDs: [tgtID, srcID])
            flatNodes[target] = .folder(folder)
            createdFolder = folder
        }

        flatNodes.remove(at: source)
        repaginate()
        save()
        return createdFolder
    }

    func renameFolder(id: UUID, to name: String) {
        for i in flatNodes.indices {
            if case .folder(var f) = flatNodes[i], f.id == id {
                f.name = name
                flatNodes[i] = .folder(f)
                break
            }
        }
        repaginate()
        save()
    }

    /// Removes an app from a folder. The app is re-inserted into the flat
    /// list immediately after the folder it came out of, so it lands in a
    /// predictable spot on the main grid.
    func removeAppFromFolder(folderID: UUID, appID: UUID) {
        var folderIndex: Int?
        var folderEmpty = false
        for i in flatNodes.indices {
            if case .folder(var f) = flatNodes[i], f.id == folderID {
                f.appIDs.removeAll { $0 == appID }
                if f.appIDs.isEmpty {
                    folderEmpty = true
                    flatNodes.remove(at: i)
                } else {
                    flatNodes[i] = .folder(f)
                }
                folderIndex = i
                break
            }
        }
        guard let idx = folderIndex else { return }
        let insertAt = folderEmpty ? idx : idx + 1
        flatNodes.insert(.app(appID), at: min(insertAt, flatNodes.count))
        repaginate()
        save()
    }

    // MARK: Reload + persistence

    private struct Persisted: Codable {
        var apps: [UUID: AppItem]
        var flat: [LayoutNode]
    }

    private func loadPersisted() -> Persisted {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else {
            return Persisted(apps: [:], flat: [])
        }
        return decoded
    }

    func save() {
        let snapshot = Persisted(apps: apps, flat: flatNodes)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func reload() {
        let scanned = AppScanner.scan()
        let persisted = loadPersisted()

        var urlToID: [URL: UUID] = [:]
        for item in persisted.apps.values {
            urlToID[item.bundleURL.standardizedFileURL] = item.id
        }

        var freshApps: [UUID: AppItem] = [:]
        for item in scanned {
            let key = item.bundleURL.standardizedFileURL
            let id = urlToID[key] ?? item.id
            freshApps[id] = AppItem(id: id, name: item.name, bundleURL: item.bundleURL)
        }
        self.apps = freshApps
        iconCache = iconCache.filter { freshApps[$0.key] != nil }
        searchIndex = freshApps.values
            .map { (id: $0.id, lowered: $0.name.lowercased()) }

        // Restore saved order, pruning anything no longer on disk.
        var placed = Set<UUID>()
        var restored: [LayoutNode] = []
        for node in persisted.flat {
            switch node {
            case .app(let id):
                if freshApps[id] != nil {
                    placed.insert(id)
                    restored.append(.app(id))
                }
            case .folder(var f):
                f.appIDs = f.appIDs.filter { freshApps[$0] != nil }
                if !f.appIDs.isEmpty {
                    placed.formUnion(f.appIDs)
                    restored.append(.folder(f))
                }
            }
        }

        // Append new apps in alphabetical order.
        let newcomers = freshApps.values
            .filter { !placed.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        restored.append(contentsOf: newcomers.map { .app($0.id) })

        self.flatNodes = restored
        repaginate()
        save()
    }

    // MARK: Live reorder preview
    //
    // The UI wants to show a reflow as the user drags, *without* committing
    // the move until drop. This helper returns what `flatNodes` would look
    // like if the item at `from` were dropped at `to`, leaving the real
    // store untouched.

    func previewFlat(movingFrom from: Int?, to: Int?) -> [LayoutNode] {
        guard let from, let to,
              from != to,
              flatNodes.indices.contains(from) else { return flatNodes }
        var list = flatNodes
        let clampedTo = min(max(to, 0), list.count - 1)
        let item = list.remove(at: from)
        list.insert(item, at: clampedTo)
        return list
    }
}

import Foundation
import Observation
import AppKit

/// Ordered, sparse slot-based layout store.
///
/// Layout model:
///   • A single flat list of slots, each one either an app, a folder, or nil.
///     nil slots are preserved — this is how "free placement with gaps" works.
///   • The grid view asks for a paginated projection (`pages`) based on the
///     current screen-derived page size. Changing page size reflows the flat
///     list without mutating it, so the user's relative order survives window
///     resizes / fullscreen toggles.
///   • Mutations are flat-index based (Int), so dragging across pages is just
///     a swap between two flat indices. No IndexPath juggling.
@Observable
final class LayoutStore {
    private(set) var apps: [UUID: AppItem] = [:]

    /// Paginated view of `flatSlots`. Each page has exactly `pageSize` slots,
    /// padded with trailing nils on the last page.
    private(set) var pages: [[LayoutNode?]] = []

    /// How many slots fit per visible page. ContentView sets this from the
    /// GeometryReader-derived (cols × rows) so the grid fills the window.
    var pageSize: Int = 35 {
        didSet { if oldValue != pageSize { paginateFromFlat(flatSlots) } }
    }

    /// Ground truth: the user's full layout as a single ordered list of
    /// optional slots. nil = empty slot.
    @ObservationIgnored private var flatSlots: [LayoutNode?] = []

    @ObservationIgnored private var searchIndex: [(id: UUID, lowered: String)] = []
    @ObservationIgnored private var iconCache: [UUID: NSImage] = [:]

    private let defaultsKey = "LaunchpadOrg.layout.v2"

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

    // MARK: Flat ↔ Paginated bridge

    /// Flatten `pages` back to a single slot list. Trailing nils trimmed.
    private func flattenPages() -> [LayoutNode?] {
        var flat: [LayoutNode?] = pages.flatMap { $0 }
        while flat.last == .some(nil) || (flat.last.flatMap { $0 } == nil && !flat.isEmpty) {
            if flat.last == nil { break }      // outer Optional (no elements)
            if flat.last! == nil { flat.removeLast() } else { break }
        }
        return flat
    }

    private func paginateFromFlat(_ flat: [LayoutNode?]) {
        flatSlots = flat
        var rebuilt: [[LayoutNode?]] = []
        var idx = 0
        let size = max(pageSize, 1)
        while idx < flat.count {
            let end = min(idx + size, flat.count)
            var page = Array(flat[idx ..< end])
            while page.count < size { page.append(nil) }
            rebuilt.append(page)
            idx = end
        }
        if rebuilt.isEmpty {
            rebuilt = [Array(repeating: nil, count: size)]
        }
        self.pages = rebuilt
    }

    /// Convert a (page, index) pair to a flat index in `flatSlots`.
    func flatIndex(page: Int, item: Int) -> Int { page * pageSize + item }

    // MARK: Mutations (flat-index based)

    /// Swap the contents of two flat slots. No shifting: everything else
    /// stays put. This is the primitive behind "drop on icon = reorder"
    /// and "drop on empty slot = move there".
    func swap(from source: Int, to target: Int) {
        guard source != target else { return }
        var flat = flatSlots
        let bound = max(source, target)
        while flat.count <= bound { flat.append(nil) }
        let a = flat[source]
        let b = flat[target]
        flat[source] = b
        flat[target] = a
        paginateFromFlat(flat)
        save()
    }

    /// Drop source onto target with folder-creation semantics.
    ///  • source is app / target is folder → add app to folder, blank source.
    ///  • source is app / target is app    → create new folder from both.
    ///  • otherwise → noop (caller should fall back to `swap`).
    @discardableResult
    func mergeOnto(source: Int, target: Int) -> AppFolder? {
        guard source != target else { return nil }
        var flat = flatSlots
        let bound = max(source, target)
        while flat.count <= bound { flat.append(nil) }
        guard case let .app(srcID)? = flat[source] else { return nil }
        switch flat[target] {
        case .folder(var folder)?:
            if !folder.appIDs.contains(srcID) { folder.appIDs.append(srcID) }
            flat[target] = .folder(folder)
            flat[source] = nil
            paginateFromFlat(flat)
            save()
            return nil
        case .app(let tgtID)?:
            let folder = AppFolder(name: "Untitled", appIDs: [tgtID, srcID])
            flat[target] = .folder(folder)
            flat[source] = nil
            paginateFromFlat(flat)
            save()
            return folder
        case nil:
            return nil
        }
    }

    func renameFolder(id: UUID, to name: String) {
        var flat = flatSlots
        for i in flat.indices {
            if case .folder(var f)? = flat[i], f.id == id {
                f.name = name
                flat[i] = .folder(f)
                break
            }
        }
        paginateFromFlat(flat)
        save()
    }

    /// Remove an app from a folder and put it back on the grid (first empty
    /// slot, or at the end if none is available).
    func removeAppFromFolder(folderID: UUID, appID: UUID) {
        var flat = flatSlots
        var found = false
        for i in flat.indices {
            if case .folder(var f)? = flat[i], f.id == folderID {
                f.appIDs.removeAll { $0 == appID }
                flat[i] = f.appIDs.isEmpty ? nil : .folder(f)
                found = true
                break
            }
        }
        guard found else { return }
        if let empty = flat.firstIndex(where: { $0 == nil }) {
            flat[empty] = .app(appID)
        } else {
            flat.append(.app(appID))
        }
        paginateFromFlat(flat)
        save()
    }

    // MARK: Reload + persistence

    private struct Persisted: Codable {
        var apps: [UUID: AppItem]
        var flat: [LayoutNode?]
    }

    private func loadPersisted() -> Persisted {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else {
            return Persisted(apps: [:], flat: [])
        }
        return decoded
    }

    func save() {
        let snapshot = Persisted(apps: apps, flat: flatSlots)
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

        // Restore persisted positions, preserving nil slots.
        var placed = Set<UUID>()
        var flat: [LayoutNode?] = persisted.flat.map { slot in
            switch slot {
            case .app(let id)?:
                if freshApps[id] != nil {
                    placed.insert(id)
                    return .app(id)
                }
                return nil
            case .folder(var f)?:
                f.appIDs = f.appIDs.filter { freshApps[$0] != nil }
                if f.appIDs.isEmpty { return nil }
                placed.formUnion(f.appIDs)
                return .folder(f)
            case nil:
                return nil
            }
        }

        // Place new apps alphabetically in the first available empty slot.
        let newcomers = freshApps.values
            .filter { !placed.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for app in newcomers {
            if let empty = flat.firstIndex(where: { $0 == nil }) {
                flat[empty] = .app(app.id)
            } else {
                flat.append(.app(app.id))
            }
        }

        paginateFromFlat(flat)
        save()
    }
}

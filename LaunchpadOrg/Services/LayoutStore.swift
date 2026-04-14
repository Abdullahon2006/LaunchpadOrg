import Foundation
import Observation

@Observable
final class LayoutStore {
    /// All apps discovered on disk, keyed by ID for fast lookup.
    private(set) var apps: [UUID: AppItem] = [:]

    /// User-arranged layout: pages of nodes (apps or folders).
    var pages: [[LayoutNode]] = []

    private let defaultsKey = "LaunchpadOrg.layout.v1"
    private let pageSize = 35 // 7 columns x 5 rows

    init() {
        reload()
    }

    /// Rescan /Applications and merge with persisted layout.
    func reload() {
        let scanned = AppScanner.scan()
        // Preserve stable IDs by URL across launches.
        let persisted = loadPersisted()

        var urlToID: [URL: UUID] = [:]
        for item in persisted.apps.values {
            urlToID[item.bundleURL.standardizedFileURL] = item.id
        }

        var freshApps: [UUID: AppItem] = [:]
        var remappedScanned: [AppItem] = []
        for item in scanned {
            let key = item.bundleURL.standardizedFileURL
            let id = urlToID[key] ?? item.id
            let final = AppItem(id: id, name: item.name, bundleURL: item.bundleURL)
            freshApps[id] = final
            remappedScanned.append(final)
        }
        self.apps = freshApps

        // Rebuild pages: keep persisted order where apps still exist, append new ones.
        var placedIDs = Set<UUID>()
        var rebuiltPages: [[LayoutNode]] = []
        for page in persisted.pages {
            var newPage: [LayoutNode] = []
            for node in page {
                switch node {
                case .app(let id):
                    if freshApps[id] != nil {
                        newPage.append(.app(id))
                        placedIDs.insert(id)
                    }
                case .folder(var folder):
                    folder.appIDs = folder.appIDs.filter { freshApps[$0] != nil }
                    placedIDs.formUnion(folder.appIDs)
                    if !folder.appIDs.isEmpty {
                        newPage.append(.folder(folder))
                    }
                }
            }
            if !newPage.isEmpty { rebuiltPages.append(newPage) }
        }

        // Append apps not yet placed.
        var leftovers: [LayoutNode] = remappedScanned
            .filter { !placedIDs.contains($0.id) }
            .map { .app($0.id) }

        if rebuiltPages.isEmpty, leftovers.isEmpty {
            rebuiltPages = [[]]
        }

        while !leftovers.isEmpty {
            if rebuiltPages.isEmpty { rebuiltPages.append([]) }
            let lastIdx = rebuiltPages.count - 1
            let space = pageSize - rebuiltPages[lastIdx].count
            if space <= 0 {
                rebuiltPages.append([])
                continue
            }
            let take = min(space, leftovers.count)
            rebuiltPages[lastIdx].append(contentsOf: leftovers.prefix(take))
            leftovers.removeFirst(take)
        }

        self.pages = rebuiltPages
        save()
    }

    // MARK: Persistence

    private struct Persisted: Codable {
        var apps: [UUID: AppItem]
        var pages: [[LayoutNode]]
    }

    private func loadPersisted() -> Persisted {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data)
        else {
            return Persisted(apps: [:], pages: [])
        }
        return decoded
    }

    func save() {
        let snapshot = Persisted(apps: apps, pages: pages)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: Mutations

    /// Move a node from one location to another. Source/target use (pageIndex, nodeIndex).
    func move(from source: IndexPath, to destination: IndexPath) {
        guard source != destination,
              pages.indices.contains(source.section),
              pages[source.section].indices.contains(source.item) else { return }
        let node = pages[source.section].remove(at: source.item)
        var destPage = destination.section
        var destItem = destination.item
        if destPage >= pages.count { destPage = pages.count - 1; destItem = pages[destPage].count }
        if source.section == destPage, destItem > pages[destPage].count {
            destItem = pages[destPage].count
        }
        pages[destPage].insert(node, at: min(destItem, pages[destPage].count))
        save()
    }

    /// Drop node `source` onto node at `target`. If both are apps, create a folder. If target is a folder, add to it.
    func dropOnto(source: IndexPath, target: IndexPath) {
        guard source != target,
              pages.indices.contains(source.section),
              pages[source.section].indices.contains(source.item),
              pages.indices.contains(target.section),
              pages[target.section].indices.contains(target.item) else { return }

        let sourceNode = pages[source.section][source.item]
        let targetNode = pages[target.section][target.item]

        switch (sourceNode, targetNode) {
        case (.app(let srcID), .app(let tgtID)):
            // Create a new folder containing both.
            let folder = AppFolder(name: "New Folder", appIDs: [tgtID, srcID])
            pages[target.section][target.item] = .folder(folder)
            pages[source.section].remove(at: source.item)
        case (.app(let srcID), .folder(var folder)):
            if !folder.appIDs.contains(srcID) { folder.appIDs.append(srcID) }
            pages[target.section][target.item] = .folder(folder)
            pages[source.section].remove(at: source.item)
        default:
            // Fallback: just reorder.
            move(from: source, to: target)
            return
        }
        save()
    }

    func renameFolder(id: UUID, to newName: String) {
        for (p, page) in pages.enumerated() {
            for (i, node) in page.enumerated() {
                if case .folder(var folder) = node, folder.id == id {
                    folder.name = newName
                    pages[p][i] = .folder(folder)
                    save()
                    return
                }
            }
        }
    }

    func removeAppFromFolder(folderID: UUID, appID: UUID) {
        for (p, page) in pages.enumerated() {
            for (i, node) in page.enumerated() {
                if case .folder(var folder) = node, folder.id == folderID {
                    folder.appIDs.removeAll { $0 == appID }
                    if folder.appIDs.isEmpty {
                        pages[p].remove(at: i)
                    } else {
                        pages[p][i] = .folder(folder)
                    }
                    // Re-add the app at end of the same page.
                    if !folder.appIDs.contains(appID) {
                        pages[p].append(.app(appID))
                    }
                    save()
                    return
                }
            }
        }
    }

    // MARK: Queries

    func app(for id: UUID) -> AppItem? { apps[id] }

    func search(_ query: String) -> [AppItem] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return apps.values
            .filter { $0.name.lowercased().contains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

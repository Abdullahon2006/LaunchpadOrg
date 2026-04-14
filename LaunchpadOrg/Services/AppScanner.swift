import Foundation
import AppKit

enum AppScanner {
    static let searchPaths: [URL] = {
        var urls: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities")
        ]
        if let home = FileManager.default.homeDirectoryForCurrentUser as URL? {
            urls.append(home.appendingPathComponent("Applications"))
        }
        return urls
    }()

    static func scan() -> [AppItem] {
        let fm = FileManager.default
        var seen = Set<String>()
        var items: [AppItem] = []

        for dir in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                let path = url.standardizedFileURL.path
                guard !seen.contains(path) else { continue }
                seen.insert(path)

                let name = displayName(for: url)
                items.append(AppItem(name: name, bundleURL: url))
            }
        }

        items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return items
    }

    private static func displayName(for url: URL) -> String {
        if let bundle = Bundle(url: url),
           let info = bundle.infoDictionary {
            if let display = info["CFBundleDisplayName"] as? String, !display.isEmpty {
                return display
            }
            if let name = info["CFBundleName"] as? String, !name.isEmpty {
                return name
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

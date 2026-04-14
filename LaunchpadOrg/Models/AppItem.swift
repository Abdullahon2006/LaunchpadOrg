import Foundation

struct AppItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var bundleURL: URL

    init(id: UUID = UUID(), name: String, bundleURL: URL) {
        self.id = id
        self.name = name
        self.bundleURL = bundleURL
    }
}

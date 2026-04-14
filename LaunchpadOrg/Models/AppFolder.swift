import Foundation

struct AppFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var appIDs: [UUID]

    init(id: UUID = UUID(), name: String = "Folder", appIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }
}

enum LayoutNode: Codable, Hashable, Identifiable {
    case app(UUID)
    case folder(AppFolder)

    var id: UUID {
        switch self {
        case .app(let id): return id
        case .folder(let folder): return folder.id
        }
    }
}

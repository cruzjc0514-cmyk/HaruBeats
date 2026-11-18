import Foundation

struct Playlist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var songFileNames: [String]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, songFileNames: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.songFileNames = songFileNames
        self.createdAt = createdAt
    }
}
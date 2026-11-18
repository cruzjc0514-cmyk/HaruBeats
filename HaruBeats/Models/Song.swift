import Foundation
import AVFoundation
import UIKit

struct Song: Identifiable, Hashable {
    let id: UUID
    let fileURL: URL
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkData: Data?

    var artworkImage: UIImage? {
        guard let data = artworkData else { return nil }
        return UIImage(data: data)
    }

    static func from(url: URL) async -> Song {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Artista desconocido"
        var album = "Álbum desconocido"
        var artworkData: Data? = nil
        var duration: TimeInterval = 0

        if let loadedDuration = try? await asset.load(.duration) {
            duration = CMTimeGetSeconds(loadedDuration)
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let val = try? await item.load(.stringValue), !val.isEmpty {
                        title = val
                    }
                case .commonKeyArtist:
                    if let val = try? await item.load(.stringValue), !val.isEmpty {
                        artist = val
                    }
                case .commonKeyAlbumName:
                    if let val = try? await item.load(.stringValue), !val.isEmpty {
                        album = val
                    }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue) {
                        artworkData = data
                    }
                default:
                    break
                }
            }
        }

        return Song(
            id: UUID(),
            fileURL: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration.isNaN ? 0 : duration,
            artworkData: artworkData
        )
    }
}
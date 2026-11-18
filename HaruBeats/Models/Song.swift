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

        // 1. Si es FLAC, leer metadatos y carátula directamente de los bloques Vorbis/Picture
        if url.pathExtension.lowercased() == "flac" {
            let flacMeta = FLACMetadataParser.parse(url: url)
            if let t = flacMeta.title, !t.isEmpty { title = t }
            if let a = flacMeta.artist, !a.isEmpty { artist = a }
            if let al = flacMeta.album, !al.isEmpty { album = al }
            if let art = flacMeta.artworkData { artworkData = art }
        }

        // 2. Respaldo con AVFoundation (para MP3, M4A, ALAC o etiquetas adicionales)
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if title == url.deletingPathExtension().lastPathComponent,
                       let val = try? await item.load(.stringValue), !val.isEmpty {
                        title = val
                    }
                case .commonKeyArtist:
                    if artist == "Artista desconocido",
                       let val = try? await item.load(.stringValue), !val.isEmpty {
                        artist = val
                    }
                case .commonKeyAlbumName:
                    if album == "Álbum desconocido",
                       let val = try? await item.load(.stringValue), !val.isEmpty {
                        album = val
                    }
                case .commonKeyArtwork:
                    if artworkData == nil,
                       let data = try? await item.load(.dataValue) {
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
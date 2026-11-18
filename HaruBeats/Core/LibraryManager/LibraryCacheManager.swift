import Foundation
import UIKit

struct CachedSongRecord: Codable {
    let fileName: String
    let fileSize: Int64
    let modificationTimestamp: TimeInterval
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let trackNumber: Int
    let discNumber: Int
    let year: String?
    let genre: String?
    let embeddedLyrics: String?
    let duration: TimeInterval
    let codec: String
    let sampleRate: Double
    let bitDepth: Int?
    let replayGainDB: Double?
    let artworkCacheKey: String?
}

final class LibraryCacheManager {
    static let shared = LibraryCacheManager()

    private let memoryThumbCache = NSCache<NSString, UIImage>()
    private let memoryFullCache = NSCache<NSString, UIImage>()

    private var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private var artworkCacheFolder: URL {
        let folder = cachesDirectory.appendingPathComponent("HaruBeatsArtwork", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private var indexFileURL: URL {
        cachesDirectory.appendingPathComponent("harubeats_library_index.json")
    }

    private init() {
        memoryThumbCache.countLimit = 400
        memoryFullCache.countLimit = 30
    }

    func loadIndex() -> [String: CachedSongRecord] {
        guard FileManager.default.fileExists(atPath: indexFileURL.path),
              let data = try? Data(contentsOf: indexFileURL),
              let records = try? JSONDecoder().decode([CachedSongRecord].self, from: data) else {
            return [:]
        }
        var dict: [String: CachedSongRecord] = [:]
        for record in records {
            dict[record.fileName] = record
        }
        return dict
    }

    func saveIndex(_ records: [CachedSongRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: indexFileURL, options: .atomic)
    }

    func storeArtwork(data: Data, forKey key: String) {
        guard let original = UIImage(data: data) else { return }

        let fullURL = artworkCacheFolder.appendingPathComponent("\(key)_full.jpg")
        let thumbURL = artworkCacheFolder.appendingPathComponent("\(key)_thumb.jpg")

        if let fullJpeg = original.jpegData(compressionQuality: 0.88) {
            try? fullJpeg.write(to: fullURL, options: .atomic)
            memoryFullCache.setObject(original, forKey: key as NSString)
        }

        let thumb = resizeImage(original, maxDimension: 180)
        if let thumbJpeg = thumb.jpegData(compressionQuality: 0.80) {
            try? thumbJpeg.write(to: thumbURL, options: .atomic)
            memoryThumbCache.setObject(thumb, forKey: key as NSString)
        }
    }

    func thumbnailImage(forKey key: String?) -> UIImage? {
        guard let key else { return nil }
        if let cached = memoryThumbCache.object(forKey: key as NSString) {
            return cached
        }
        let thumbURL = artworkCacheFolder.appendingPathComponent("\(key)_thumb.jpg")
        if let img = UIImage(contentsOfFile: thumbURL.path) {
            memoryThumbCache.setObject(img, forKey: key as NSString)
            return img
        }
        return fullImage(forKey: key)
    }

    func fullImage(forKey key: String?) -> UIImage? {
        guard let key else { return nil }
        if let cached = memoryFullCache.object(forKey: key as NSString) {
            return cached
        }
        let fullURL = artworkCacheFolder.appendingPathComponent("\(key)_full.jpg")
        if let img = UIImage(contentsOfFile: fullURL.path) {
            memoryFullCache.setObject(img, forKey: key as NSString)
            return img
        }
        return nil
    }

    func removeArtwork(forKey key: String?) {
        guard let key else { return }
        memoryThumbCache.removeObject(forKey: key as NSString)
        memoryFullCache.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: artworkCacheFolder.appendingPathComponent("\(key)_full.jpg"))
        try? FileManager.default.removeItem(at: artworkCacheFolder.appendingPathComponent("\(key)_thumb.jpg"))
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let ratio = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let targetSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
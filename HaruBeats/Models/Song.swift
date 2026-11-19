import Foundation
import AVFoundation
import UIKit

struct Song: Identifiable, Hashable {
    let id: UUID
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
    let fileURL: URL
    let relativePath: String
    let artworkCacheKey: String?
    let codec: String
    let sampleRate: Double
    let bitDepth: Int?
    let replayGainDB: Double?
    let replayGainPeak: Double?

    var thumbnailImage: UIImage? {
        LibraryCacheManager.shared.thumbnailImage(forKey: artworkCacheKey)
    }

    var artworkImage: UIImage? {
        LibraryCacheManager.shared.fullImage(forKey: artworkCacheKey)
    }

    var audioQualityBadge: String {
        var parts: [String] = [codec]
        if let bitDepth, bitDepth > 0 {
            parts.append("\(bitDepth)-bit")
        }
        if sampleRate > 0 {
            let khz = sampleRate / 1000.0
            if khz.truncatingRemainder(dividingBy: 1) == 0 {
                parts.append(String(format: "%.0f kHz", khz))
            } else {
                parts.append(String(format: "%.1f kHz", khz))
            }
        }
        return parts.joined(separator: " · ")
    }

    var isHiRes: Bool {
        (bitDepth ?? 16) >= 24 || sampleRate > 48000
    }

    /// Ganancia segura en dB limitada por REPLAYGAIN_*_PEAK (-20 * log10(peak)) para evitar clipping
    var safeReplayGainDB: Float {
        guard let rawDB = replayGainDB else { return 0 }
        var effectiveDB = rawDB
        if let peak = replayGainPeak, peak > 0 {
            let maxGainBeforeClipDB = -20.0 * log10(peak)
            if effectiveDB > maxGainBeforeClipDB {
                effectiveDB = maxGainBeforeClipDB
            }
        }
        return Float(min(max(effectiveDB, -15.0), 12.0))
    }

    func toCachedRecord(fileSize: Int64, modTime: TimeInterval) -> CachedSongRecord {
        CachedSongRecord(
            relativePath: relativePath,
            fileSize: fileSize,
            modificationTimestamp: modTime,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            genre: genre,
            embeddedLyrics: embeddedLyrics,
            duration: duration,
            codec: codec,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            replayGainDB: replayGainDB,
            replayGainPeak: replayGainPeak,
            artworkCacheKey: artworkCacheKey
        )
    }

    static func fromCached(_ record: CachedSongRecord, fileURL: URL) -> Song {
        Song(
            id: UUID(),
            title: record.title,
            artist: record.artist,
            album: record.album,
            albumArtist: record.albumArtist,
            trackNumber: record.trackNumber,
            discNumber: record.discNumber,
            year: record.year,
            genre: record.genre,
            embeddedLyrics: record.embeddedLyrics,
            duration: record.duration,
            fileURL: fileURL,
            relativePath: record.relativePath,
            artworkCacheKey: record.artworkCacheKey,
            codec: record.codec,
            sampleRate: record.sampleRate,
            bitDepth: record.bitDepth,
            replayGainDB: record.replayGainDB,
            replayGainPeak: record.replayGainPeak
        )
    }

    static func from(url: URL, relativePath: String) async -> Song {
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.uppercased()
        let codecName = ext.isEmpty ? "AUDIO" : ext

        var title = fallbackTitle
        var artist = "Artista desconocido"
        var album = "Álbum desconocido"
        var albumArtist: String? = nil
        var trackNumber = 0
        var discNumber = 1
        var year: String? = nil
        var genre: String? = nil
        var embeddedLyrics: String? = nil
        var artworkData: Data? = nil
        var durationSeconds: TimeInterval = 0
        var sampleRate: Double = 44100
        var bitDepth: Int? = nil
        var replayGainDB: Double? = nil
        var replayGainPeak: Double? = nil

        if let audioFile = try? AVAudioFile(forReading: url) {
            let fmt = audioFile.fileFormat
            if fmt.sampleRate > 0 {
                sampleRate = fmt.sampleRate
                durationSeconds = Double(audioFile.length) / fmt.sampleRate
            }
            if let depth = fmt.settings[AVLinearPCMBitDepthKey] as? Int, depth > 0 {
                bitDepth = depth
            }
        }

        if url.pathExtension.lowercased() == "flac" {
            let flacMeta = FLACMetadataParser.parse(url: url)
            if let t = flacMeta.title { title = t }
            if let a = flacMeta.artist { artist = a }
            if let al = flacMeta.album { album = al }
            if let aa = flacMeta.albumArtist { albumArtist = aa }
            if let tn = flacMeta.trackNumber { trackNumber = tn }
            if let dn = flacMeta.discNumber { discNumber = dn }
            if let yr = flacMeta.year { year = yr }
            if let gn = flacMeta.genre { genre = gn }
            if let lyr = flacMeta.embeddedLyrics { embeddedLyrics = lyr }
            if let art = flacMeta.artworkData { artworkData = art }
            if let sr = flacMeta.sampleRate, sr > 0 { sampleRate = sr }
            if let bd = flacMeta.bitDepth { bitDepth = bd }
            replayGainDB = flacMeta.replayGainTrackDB ?? flacMeta.replayGainAlbumDB
            replayGainPeak = flacMeta.replayGainTrackPeak ?? flacMeta.replayGainAlbumPeak
        } else {
            let asset = AVURLAsset(url: url)
            if durationSeconds == 0, let assetDuration = try? await asset.load(.duration) {
                let secs = CMTimeGetSeconds(assetDuration)
                if secs.isFinite && secs > 0 { durationSeconds = secs }
            }

            if let metadata = try? await asset.load(.commonMetadata) {
                for item in metadata {
                    guard let commonKey = item.commonKey else { continue }
                    switch commonKey {
                    case .commonKeyTitle:
                        if let val = try? await item.load(.stringValue), !val.isEmpty { title = val }
                    case .commonKeyArtist:
                        if let val = try? await item.load(.stringValue), !val.isEmpty { artist = val }
                    case .commonKeyAlbumName:
                        if let val = try? await item.load(.stringValue), !val.isEmpty { album = val }
                    case .commonKeyCreator:
                        if let val = try? await item.load(.stringValue), !val.isEmpty { albumArtist = val }
                    case .commonKeyType:
                        if let val = try? await item.load(.stringValue), !val.isEmpty { genre = val }
                    case .commonKeyArtwork:
                        if let data = try? await item.load(.dataValue) { artworkData = data }
                    default:
                        break
                    }
                }
            }

            if let lyricsText = try? await asset.load(.lyrics), !lyricsText.isEmpty {
                embeddedLyrics = lyricsText
            }
        }

        let resolvedAlbumArtist = (albumArtist?.isEmpty == false) ? albumArtist! : artist
        var cacheKey: String? = nil
        if let artworkData {
            let safeAlbumKey = relativePath
                .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
            cacheKey = String(safeAlbumKey.prefix(90))
            LibraryCacheManager.shared.storeArtwork(data: artworkData, forKey: cacheKey!)
        }

        return Song(
            id: UUID(),
            title: title,
            artist: artist,
            album: album,
            albumArtist: resolvedAlbumArtist,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            genre: genre,
            embeddedLyrics: embeddedLyrics,
            duration: durationSeconds,
            fileURL: url,
            relativePath: relativePath,
            artworkCacheKey: cacheKey,
            codec: codecName,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            replayGainDB: replayGainDB,
            replayGainPeak: replayGainPeak
        )
    }
}

extension Song {
    var formattedDuration: String {
        guard duration.isFinite, duration > 0 else { return "0:00" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
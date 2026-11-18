import Foundation
import AVFoundation
import UIKit

struct Song: Identifiable, Hashable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let fileURL: URL
    let artworkData: Data?
    let codec: String
    let sampleRate: Double
    let bitDepth: Int?
    let replayGainDB: Double?

    var artworkImage: UIImage? {
        guard let artworkData else { return nil }
        return UIImage(data: artworkData)
    }

    /// Etiqueta audiófila formateada (ej. "FLAC · 24-bit · 96 kHz" o "M4A · 44.1 kHz")
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

    static func from(url: URL) async -> Song {
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.uppercased()
        let codecName = ext.isEmpty ? "AUDIO" : ext

        var title = fallbackTitle
        var artist = "Artista desconocido"
        var album = "Álbum desconocido"
        var artworkData: Data? = nil
        var durationSeconds: TimeInterval = 0
        var sampleRate: Double = 44100
        var bitDepth: Int? = nil
        var replayGainDB: Double? = nil

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
            if let art = flacMeta.artworkData { artworkData = art }
            if let sr = flacMeta.sampleRate, sr > 0 { sampleRate = sr }
            if let bd = flacMeta.bitDepth { bitDepth = bd }
            replayGainDB = flacMeta.replayGainTrackDB ?? flacMeta.replayGainAlbumDB
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
                    case .commonKeyArtwork:
                        if let data = try? await item.load(.dataValue) { artworkData = data }
                    default:
                        break
                    }
                }
            }
        }

        return Song(
            id: UUID(),
            title: title,
            artist: artist,
            album: album,
            duration: durationSeconds,
            fileURL: url,
            artworkData: artworkData,
            codec: codecName,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            replayGainDB: replayGainDB
        )
    }
}
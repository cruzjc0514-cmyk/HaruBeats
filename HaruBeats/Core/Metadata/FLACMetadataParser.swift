import Foundation
import UIKit

struct FLACMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var artworkData: Data?
    var sampleRate: Double?
    var bitDepth: Int?
    var replayGainTrackDB: Double?
    var replayGainAlbumDB: Double?
}

enum FLACMetadataParser {
    static func parse(url: URL) -> FLACMetadata {
        var result = FLACMetadata()
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count > 8 else {
            return result
        }

        // Verificar cabecera mágica "fLaC"
        guard data[0] == 0x66, data[1] == 0x4C, data[2] == 0x61, data[3] == 0x43 else {
            return result
        }

        var offset = 4
        var isLastBlock = false

        while !isLastBlock && offset + 4 <= data.count {
            let headerByte = data[offset]
            isLastBlock = (headerByte & 0x80) != 0
            let blockType = headerByte & 0x7F

            let length = (Int(data[offset + 1]) << 16)
                       | (Int(data[offset + 2]) << 8)
                       | Int(data[offset + 3])
            offset += 4

            guard length >= 0, offset + length <= data.count else { break }
            let blockData = data.subdata(in: offset..<(offset + length))

            if blockType == 0 {
                // STREAMINFO: sampleRate (20 bits desde byte 10) y bitDepth (5 bits desde byte 12)
                parseStreamInfo(blockData, into: &result)
            } else if blockType == 4 {
                // VORBIS_COMMENT
                parseVorbisComment(blockData, into: &result)
            } else if blockType == 6 {
                // PICTURE
                if result.artworkData == nil {
                    result.artworkData = parsePictureBlock(blockData)
                }
            }

            offset += length
        }

        return result
    }

    private static func parseStreamInfo(_ block: Data, into metadata: inout FLACMetadata) {
        guard block.count >= 14 else { return }
        // Bytes 10..13 contienen: sampleRate (20 bits) | channels-1 (3 bits) | bps-1 (5 bits) | totalSamples (4 bits altos)
        let b10 = UInt32(block[10])
        let b11 = UInt32(block[11])
        let b12 = UInt32(block[12])
        let b13 = UInt32(block[13])

        let sampleRate = (b10 << 12) | (b11 << 4) | (b12 >> 4)
        let bpsMinusOne = ((b12 & 0x01) << 4) | (b13 >> 4)

        if sampleRate > 0 {
            metadata.sampleRate = Double(sampleRate)
        }
        let bits = Int(bpsMinusOne) + 1
        if bits >= 8 && bits <= 32 {
            metadata.bitDepth = bits
        }
    }

    private static func parseVorbisComment(_ block: Data, into metadata: inout FLACMetadata) {
        var pos = 0
        guard pos + 4 <= block.count else { return }

        let vendorLength = Int(readUInt32LE(block, at: pos))
        pos += 4 + vendorLength
        guard pos + 4 <= block.count else { return }

        let commentCount = Int(readUInt32LE(block, at: pos))
        pos += 4

        for _ in 0..<commentCount {
            guard pos + 4 <= block.count else { break }
            let entryLength = Int(readUInt32LE(block, at: pos))
            pos += 4
            guard entryLength >= 0, pos + entryLength <= block.count else { break }

            let entryData = block.subdata(in: pos..<(pos + entryLength))
            pos += entryLength

            if let entry = String(data: entryData, encoding: .utf8),
               let eqIndex = entry.firstIndex(of: "=") {
                let key = entry[..<eqIndex].uppercased()
                let value = String(entry[entry.index(after: eqIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                switch key {
                case "TITLE":
                    if !value.isEmpty { metadata.title = value }
                case "ARTIST":
                    if !value.isEmpty { metadata.artist = value }
                case "ALBUM":
                    if !value.isEmpty { metadata.album = value }
                case "REPLAYGAIN_TRACK_GAIN":
                    metadata.replayGainTrackDB = parseGainDB(value)
                case "REPLAYGAIN_ALBUM_GAIN":
                    metadata.replayGainAlbumDB = parseGainDB(value)
                default:
                    break
                }
            }
        }
    }

    private static func parseGainDB(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "dB", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private static func parsePictureBlock(_ block: Data) -> Data? {
        var pos = 0
        guard pos + 8 <= block.count else { return nil }
        pos += 4 // pictureType

        let mimeLength = Int(readUInt32BE(block, at: pos))
        pos += 4 + mimeLength
        guard pos + 4 <= block.count else { return nil }

        let descLength = Int(readUInt32BE(block, at: pos))
        pos += 4 + descLength
        guard pos + 20 <= block.count else { return nil }

        pos += 16 // width, height, depth, colors
        let dataLength = Int(readUInt32BE(block, at: pos))
        pos += 4

        guard dataLength > 0, pos + dataLength <= block.count else { return nil }
        return block.subdata(in: pos..<(pos + dataLength))
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
    }

    private static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
        | (UInt32(data[offset + 1]) << 16)
        | (UInt32(data[offset + 2]) << 8)
        | UInt32(data[offset + 3])
    }
}
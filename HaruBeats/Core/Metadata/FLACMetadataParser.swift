import Foundation

struct FLACMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var trackNumber: Int?
    var discNumber: Int?
    var year: String?
    var genre: String?
    var embeddedLyrics: String?
    var artworkData: Data?
    var sampleRate: Double?
    var bitDepth: Int?
    var replayGainTrackDB: Double?
    var replayGainAlbumDB: Double?
    var replayGainTrackPeak: Double?
    var replayGainAlbumPeak: Double?
}

enum FLACMetadataParser {
    static func parse(url: URL) -> FLACMetadata {
        var result = FLACMetadata()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return result }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 4),
              header.count == 4,
              String(data: header, encoding: .ascii) == "fLaC" else {
            return result
        }

        var isLastBlock = false
        while !isLastBlock {
            guard let blockHeader = try? handle.read(upToCount: 4), blockHeader.count == 4 else { break }
            let firstByte = blockHeader[0]
            isLastBlock = (firstByte & 0x80) != 0
            let blockType = firstByte & 0x7F
            let blockLength = (Int(blockHeader[1]) << 16) | (Int(blockHeader[2]) << 8) | Int(blockHeader[3])

            guard blockLength > 0, blockLength < 50_000_000 else { break }
            guard let blockData = try? handle.read(upToCount: blockLength), blockData.count == blockLength else { break }

            switch blockType {
            case 0: // STREAMINFO
                if blockData.count >= 14 {
                    let sr = (Int(blockData[10]) << 12) | (Int(blockData[11]) << 4) | ((Int(blockData[12]) & 0xF0) >> 4)
                    if sr > 0 { result.sampleRate = Double(sr) }
                    let bpsMinus1 = ((Int(blockData[12]) & 0x01) << 4) | ((Int(blockData[13]) & 0xF0) >> 4)
                    result.bitDepth = bpsMinus1 + 1
                }

            case 4: // VORBIS_COMMENT
                parseVorbisComments(data: blockData, into: &result)

            case 6: // PICTURE
                if let picData = parsePictureBlock(data: blockData) {
                    if result.artworkData == nil {
                        result.artworkData = picData
                    }
                }

            default:
                break
            }
        }

        return result
    }

    private static func parseVorbisComments(data: Data, into result: inout FLACMetadata) {
        var offset = 0
        guard data.count >= 8 else { return }

        let vendorLength = Int(readUInt32LE(data, offset: offset))
        offset += 4 + vendorLength
        guard offset + 4 <= data.count else { return }

        let commentCount = Int(readUInt32LE(data, offset: offset))
        offset += 4

        for _ in 0..<commentCount {
            guard offset + 4 <= data.count else { break }
            let length = Int(readUInt32LE(data, offset: offset))
            offset += 4
            guard length > 0, offset + length <= data.count else { break }

            let commentData = data.subdata(in: offset..<(offset + length))
            offset += length

            guard let comment = String(data: commentData, encoding: .utf8),
                  let eqIdx = comment.firstIndex(of: "=") else { continue }

            let key = comment[..<eqIdx].uppercased()
            let value = String(comment[comment.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            switch key {
            case "TITLE":
                result.title = value
            case "ARTIST":
                result.artist = value
            case "ALBUM":
                result.album = value
            case "ALBUMARTIST", "ALBUM ARTIST":
                result.albumArtist = value
            case "TRACKNUMBER":
                let clean = value.split(separator: "/").first.map(String.init) ?? value
                result.trackNumber = Int(clean)
            case "DISCNUMBER":
                let clean = value.split(separator: "/").first.map(String.init) ?? value
                result.discNumber = Int(clean)
            case "DATE", "YEAR":
                result.year = String(value.prefix(4))
            case "GENRE":
                result.genre = value
            case "LYRICS", "UNSYNCEDLYRICS", "SYNCEDLYRICS":
                if result.embeddedLyrics == nil || key == "SYNCEDLYRICS" {
                    result.embeddedLyrics = value
                }
            case "REPLAYGAIN_TRACK_GAIN":
                result.replayGainTrackDB = parseGainDB(value)
            case "REPLAYGAIN_ALBUM_GAIN":
                result.replayGainAlbumDB = parseGainDB(value)
            case "REPLAYGAIN_TRACK_PEAK":
                result.replayGainTrackPeak = Double(value)
            case "REPLAYGAIN_ALBUM_PEAK":
                result.replayGainAlbumPeak = Double(value)
            default:
                break
            }
        }
    }

    private static func parseGainDB(_ raw: String) -> Double? {
        let cleaned = raw.lowercased()
            .replacingOccurrences(of: "db", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private static func parsePictureBlock(data: Data) -> Data? {
        var offset = 0
        guard data.count >= 32 else { return nil }

        offset += 4 // picture type
        let mimeLen = Int(readUInt32BE(data, offset: offset))
        offset += 4 + mimeLen
        guard offset + 4 <= data.count else { return nil }

        let descLen = Int(readUInt32BE(data, offset: offset))
        offset += 4 + descLen
        guard offset + 20 <= data.count else { return nil }

        offset += 16 // width, height, depth, colors
        let imageLen = Int(readUInt32BE(data, offset: offset))
        offset += 4
        guard imageLen > 0, offset + imageLen <= data.count else { return nil }

        return data.subdata(in: offset..<(offset + imageLen))
    }

    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
    }

    private static func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
        | (UInt32(data[offset + 1]) << 16)
        | (UInt32(data[offset + 2]) << 8)
        | UInt32(data[offset + 3])
    }
}
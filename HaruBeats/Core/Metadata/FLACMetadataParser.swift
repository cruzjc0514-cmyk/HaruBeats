import Foundation

struct ParsedMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var artworkData: Data?
}

enum FLACMetadataParser {
    static func parse(url: URL) -> ParsedMetadata {
        var result = ParsedMetadata()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return result }
        defer { try? handle.close() }

        // Verificar firma mágica "fLaC"
        guard let header = try? handle.read(upToCount: 4),
              header == Data([0x66, 0x4C, 0x61, 0x43]) else {
            return result
        }

        var isLastBlock = false
        while !isLastBlock {
            guard let blockHeader = try? handle.read(upToCount: 4),
                  blockHeader.count == 4 else { break }

            let firstByte = blockHeader[0]
            isLastBlock = (firstByte & 0x80) != 0
            let blockType = firstByte & 0x7F

            let length = (Int(blockHeader[1]) << 16) | (Int(blockHeader[2]) << 8) | Int(blockHeader[3])
            guard length > 0, length < 20_000_000 else { break }

            if blockType == 4 { // VORBIS_COMMENT
                if let data = try? handle.read(upToCount: length) {
                    parseVorbisComments(data: data, into: &result)
                }
            } else if blockType == 6 { // PICTURE
                if let data = try? handle.read(upToCount: length) {
                    result.artworkData = parsePictureBlock(data: data)
                }
            } else {
                // Saltar otros bloques (STREAMINFO, SEEKTABLE, PADDING, etc.)
                let currentOffset = handle.offsetInFile
                try? handle.seek(toOffset: currentOffset + UInt64(length))
            }
        }
        return result
    }

    private static func parseVorbisComments(data: Data, into result: inout ParsedMetadata) {
        var offset = 0
        guard data.count >= 8 else { return }

        let vendorLength = Int(readUInt32LE(data, offset: offset))
        offset += 4 + vendorLength
        guard offset + 4 <= data.count else { return }

        let commentCount = Int(readUInt32LE(data, offset: offset))
        offset += 4

        for _ in 0..<commentCount {
            guard offset + 4 <= data.count else { break }
            let commentLength = Int(readUInt32LE(data, offset: offset))
            offset += 4
            guard offset + commentLength <= data.count else { break }

            if let comment = String(data: data.subdata(in: offset..<(offset + commentLength)), encoding: .utf8),
               let eqIndex = comment.firstIndex(of: "=") {
                let key = comment[..<eqIndex].uppercased()
                let value = String(comment[comment.index(after: eqIndex)...])
                switch key {
                case "TITLE": result.title = value
                case "ARTIST": result.artist = value
                case "ALBUM": result.album = value
                default: break
                }
            }
            offset += commentLength
        }
    }

    private static func parsePictureBlock(data: Data) -> Data? {
        var offset = 0
        guard data.count >= 32 else { return nil }

        // Saltar picture type (4 bytes)
        offset += 4
        let mimeLength = Int(readUInt32BE(data, offset: offset))
        offset += 4 + mimeLength
        guard offset + 4 <= data.count else { return nil }

        let descLength = Int(readUInt32BE(data, offset: offset))
        offset += 4 + descLength
        // Saltar width, height, depth, colors (16 bytes)
        offset += 16
        guard offset + 4 <= data.count else { return nil }

        let pictureLength = Int(readUInt32BE(data, offset: offset))
        offset += 4
        guard pictureLength > 0, offset + pictureLength <= data.count else { return nil }

        return data.subdata(in: offset..<(offset + pictureLength))
    }

    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
    }

    private static func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24) |
        (UInt32(data[offset + 1]) << 16) |
        (UInt32(data[offset + 2]) << 8) |
        UInt32(data[offset + 3])
    }
}
import SwiftUI
import UIKit

enum ArtworkColorExtractor {
    static func dominantColor(from image: UIImage?) -> Color? {
        guard let image, let cgImage = image.cgImage else { return nil }

        let width = 24
        let height = 24
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var bestR: Double = 0
        var bestG: Double = 0
        var bestB: Double = 0
        var bestScore: Double = -1

        for idx in stride(from: 0, to: rawData.count, by: 4) {
            let r = Double(rawData[idx]) / 255.0
            let g = Double(rawData[idx + 1]) / 255.0
            let b = Double(rawData[idx + 2]) / 255.0

            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            let brightness = maxC

            // Priorizar colores vivos y legibles sobre negro/blanco puros
            if brightness > 0.18 && brightness < 0.94 {
                let score = saturation * 2.2 + brightness * 0.6
                if score > bestScore {
                    bestScore = score
                    bestR = r
                    bestG = g
                    bestB = b
                }
            }
        }

        if bestScore < 0 { return nil }
        return Color(red: min(bestR * 1.12, 1.0), green: min(bestG * 1.12, 1.0), blue: min(bestB * 1.12, 1.0))
    }
}
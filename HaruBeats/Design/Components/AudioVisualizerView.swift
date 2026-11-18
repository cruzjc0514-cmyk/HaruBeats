import SwiftUI

struct AudioVisualizerView: View {
    let isPlaying: Bool
    let accentColor: Color

    @State private var animate = false

    private let heights: [CGFloat] = [0.4, 0.9, 0.6, 1.0, 0.5, 0.85, 0.45]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<heights.count, id: \.self) { idx in
                Capsule()
                    .fill(accentColor)
                    .frame(width: 3.5, height: isPlaying ? (animate ? 20 * heights[idx] : 6) : 4)
                    .animation(
                        isPlaying
                        ? .easeInOut(duration: 0.35 + Double(idx) * 0.06).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.2),
                        value: animate
                    )
            }
        }
        .frame(height: 22)
        .onAppear {
            animate = true
        }
    }
}
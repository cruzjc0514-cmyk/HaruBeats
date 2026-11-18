import Foundation

enum EqualizerPreset: String, CaseIterable, Identifiable, Codable {
    case flat = "Plano"
    case bassBoost = "Graves +"
    case vocal = "Vocal"
    case electronic = "Electrónica"
    case rock = "Rock"
    case custom = "Personalizado"

    var id: String { rawValue }

    /// Ganancias en dB para las 5 bandas: [60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz]
    var gains: [Float] {
        switch self {
        case .flat:       return [0, 0, 0, 0, 0]
        case .bassBoost:  return [6.5, 4.0, 0, -1.0, 1.0]
        case .vocal:      return [-2.0, 1.0, 4.5, 3.5, 1.0]
        case .electronic: return [5.5, 2.5, -1.5, 3.0, 5.0]
        case .rock:       return [4.5, 2.0, -1.0, 3.0, 4.5]
        case .custom:     return [0, 0, 0, 0, 0]
        }
    }
}
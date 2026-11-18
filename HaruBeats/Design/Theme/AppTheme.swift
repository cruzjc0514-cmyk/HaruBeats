import SwiftUI

enum AccentOption: String, CaseIterable, Identifiable {
    case indigo = "Índigo"
    case emerald = "Esmeralda"
    case crimson = "Carmesí"
    case amber = "Ámbar"
    case cyan = "Cian"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .indigo:  return .indigo
        case .emerald: return Color(red: 0.12, green: 0.78, blue: 0.55)
        case .crimson: return Color(red: 0.92, green: 0.24, blue: 0.36)
        case .amber:   return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .cyan:    return Color(red: 0.15, green: 0.75, blue: 0.92)
        }
    }
}

enum AppTheme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let cardBackground = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let elevatedBackground = Color(red: 0.16, green: 0.16, blue: 0.20)
    static let primaryAccent = Color.indigo
    static let secondaryText = Color(white: 0.62)
}
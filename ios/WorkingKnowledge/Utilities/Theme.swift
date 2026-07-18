import SwiftUI

/// Crystal Lattice palette carried over from the MemPalace source theme.
enum Theme {
    static let bg = Color(red: 8 / 255, green: 12 / 255, blue: 24 / 255)
    static let surface = Color(red: 15 / 255, green: 21 / 255, blue: 36 / 255)
    static let surfaceHigh = Color(red: 24 / 255, green: 32 / 255, blue: 51 / 255)
    static let border = Color(red: 28 / 255, green: 38 / 255, blue: 64 / 255)

    static let cyan = Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)
    static let cyanLight = Color(red: 125 / 255, green: 211 / 255, blue: 252 / 255)
    static let violet = Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255)

    static let ice = Color(red: 219 / 255, green: 231 / 255, blue: 245 / 255)
    static let body = Color(red: 205 / 255, green: 213 / 255, blue: 224 / 255)
    static let muted = Color(red: 139 / 255, green: 153 / 255, blue: 176 / 255)
    static let dim = Color(red: 91 / 255, green: 107 / 255, blue: 130 / 255)

    static let ok = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
    static let warn = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
    static let hot = Color(red: 255 / 255, green: 139 / 255, blue: 139 / 255)

    /// Ice → cyan → violet display gradient used for hero headings in the source.
    static let heroGradient = LinearGradient(
        colors: [ice, cyan, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cyanVioletGradient = LinearGradient(
        colors: [cyan, violet],
        startPoint: .leading,
        endPoint: .trailing
    )
}

import SwiftUI

/// Custom colour palette for `MoodTheme`. Centralised here so the mapping in
/// `MoodTheme.from` and any UI previews stay visually consistent.
extension Color {
    static let moodNeutral = Color(red: 0.55, green: 0.55, blue: 0.58)

    // High energy: electric indigo -> cyan
    static let moodElectricIndigo = Color(red: 0.36, green: 0.20, blue: 1.0)
    static let moodCyan = Color(red: 0.20, green: 0.90, blue: 1.0)

    // Mid energy: violet -> rose
    static let moodViolet = Color(red: 0.56, green: 0.27, blue: 0.93)
    static let moodRose = Color(red: 0.96, green: 0.40, blue: 0.60)

    // Calm: amber -> gold
    static let moodAmber = Color(red: 1.0, green: 0.69, blue: 0.20)
    static let moodGold = Color(red: 1.0, green: 0.84, blue: 0.40)

    // Worship/Gospel: soft gold -> white
    static let moodSoftGold = Color(red: 1.0, green: 0.91, blue: 0.70)
    static let moodWhiteGlow = Color(red: 1.0, green: 0.98, blue: 0.94)
}

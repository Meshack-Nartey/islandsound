import SwiftUI

/// Coarse classification of the currently-playing track's "mood", derived from
/// BPM, spectral energy and warmth. Drives both the colour and pulse speed of
/// the island's glow border.
enum MoodProfile: String, CaseIterable, Equatable {
    case highEnergy   // BPM > 120, high flux
    case midEnergy    // BPM 80-120
    case calm         // BPM < 80, low flux
    case worship      // warm + slow
    case none         // no music / paused
}

/// Colours + animation config the island border renders.
struct MoodTheme: Equatable {
    var primaryColor: Color
    var secondaryColor: Color
    var glowIntensity: Double // 0...1
    var pulseSpeed: Double    // seconds per pulse cycle, 0 = no animation
    var profile: MoodProfile

    /// Default theme shown when nothing is playing or the player is paused.
    static let neutral = MoodTheme(
        primaryColor: Color.moodNeutral,
        secondaryColor: Color.moodNeutral.opacity(0.4),
        glowIntensity: 0.15,
        pulseSpeed: 0,
        profile: .none
    )

    /// Maps raw audio-analysis output to a `MoodTheme`, per the mood table:
    ///
    /// | Profile                         | Colour                  | Pulse speed |
    /// |----------------------------------|-------------------------|-------------|
    /// | High energy (BPM > 120, high flux) | Electric indigo → cyan | 0.4s        |
    /// | Mid energy (BPM 80-120)          | Violet → rose            | 0.8s        |
    /// | Calm (BPM < 80, low flux)         | Amber → gold            | 1.6s        |
    /// | Worship/Gospel (warm + slow)      | Soft gold → white       | 2.4s        |
    /// | No music / paused                 | Neutral grey            | none        |
    static func from(bpm: Double, energy: Double, warmth: Double, isPlaying: Bool) -> MoodTheme {
        guard isPlaying else { return .neutral }

        let clampedEnergy = min(max(energy, 0), 1)
        let clampedWarmth = min(max(warmth, 0), 1)

        // Warm + slow material (worship/gospel) takes priority over a generic
        // "calm" classification because it has a distinct, breath-like pulse.
        if bpm < 80 && clampedWarmth > 0.6 {
            return MoodTheme(
                primaryColor: Color.moodSoftGold,
                secondaryColor: Color.moodWhiteGlow,
                glowIntensity: 0.5 + clampedWarmth * 0.3,
                pulseSpeed: 2.4,
                profile: .worship
            )
        }

        if bpm > 120 && clampedEnergy > 0.55 {
            return MoodTheme(
                primaryColor: Color.moodElectricIndigo,
                secondaryColor: Color.moodCyan,
                glowIntensity: 0.6 + clampedEnergy * 0.4,
                pulseSpeed: 0.4,
                profile: .highEnergy
            )
        }

        if bpm >= 80 && bpm <= 120 {
            return MoodTheme(
                primaryColor: Color.moodViolet,
                secondaryColor: Color.moodRose,
                glowIntensity: 0.4 + clampedEnergy * 0.4,
                pulseSpeed: 0.8,
                profile: .midEnergy
            )
        }

        // Default: calm, BPM < 80 and low flux.
        return MoodTheme(
            primaryColor: Color.moodAmber,
            secondaryColor: Color.moodGold,
            glowIntensity: 0.3 + clampedEnergy * 0.3,
            pulseSpeed: 1.6,
            profile: .calm
        )
    }

    /// Returns true if `other` differs enough from `self` to justify a visual
    /// update. Used by `MoodEngine` to throttle colour changes and prevent
    /// flickering on small spectral fluctuations.
    func shouldUpdate(to other: MoodTheme, threshold: Double = 0.08) -> Bool {
        if profile != other.profile { return true }
        if abs(pulseSpeed - other.pulseSpeed) > 0.01 { return true }
        return abs(glowIntensity - other.glowIntensity) > threshold
    }
}

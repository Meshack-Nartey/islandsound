import SwiftUI

/// Renders the pulsing mood-coloured glow border described in
/// FEATURE 1 — MOOD-BASED DYNAMIC THEMING.
///
/// The border is a rounded-rectangle stroke with a gradient between the
/// theme's primary/secondary colours, plus a soft shadow "bloom". The pulse
/// is a slow scale + opacity breathing animation whose period is
/// `theme.pulseSpeed`. A `pulseSpeed` of 0 disables the animation entirely
/// (used for `.neutral`, so paused/idle uses 0% extra CPU on animation).
struct MoodGlowBorder: ViewModifier {
    let theme: MoodTheme
    let cornerRadius: CGFloat

    @State private var pulse: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [theme.primaryColor, theme.secondaryColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.5
                    )
                    .opacity(theme.glowIntensity * (pulse ? 1.0 : 0.6))
                    .shadow(color: theme.primaryColor.opacity(theme.glowIntensity * 0.6), radius: pulse ? 6 : 2)
                    .animation(pulseAnimation, value: pulse)
            )
            .onAppear { startPulse() }
            .onChange(of: theme.pulseSpeed) { _, _ in startPulse() }
    }

    private var pulseAnimation: Animation? {
        guard theme.pulseSpeed > 0 else { return nil }
        return .easeInOut(duration: theme.pulseSpeed).repeatForever(autoreverses: true)
    }

    private func startPulse() {
        guard theme.pulseSpeed > 0 else {
            pulse = false
            return
        }
        // Toggling on the next runloop tick kicks off the repeating animation.
        pulse = false
        DispatchQueue.main.async {
            pulse = true
        }
    }
}

extension View {
    /// Applies the mood-reactive glow border from `MoodGlowBorder`.
    func moodGlow(_ theme: MoodTheme, cornerRadius: CGFloat) -> some View {
        modifier(MoodGlowBorder(theme: theme, cornerRadius: cornerRadius))
    }
}

import XCTest
@testable import IslandSound

/// Verifies `MoodTheme.from(bpm:energy:warmth:isPlaying:)` matches the mood
/// table in Section 4.2-4.3: BPM/energy/warmth combinations should map to the
/// correct `MoodProfile` and pulse speed.
final class MoodThemeTests: XCTestCase {
    func testNotPlayingAlwaysReturnsNeutral() {
        let theme = MoodTheme.from(bpm: 140, energy: 0.9, warmth: 0.9, isPlaying: false)
        XCTAssertEqual(theme, MoodTheme.neutral)
        XCTAssertEqual(theme.profile, .none)
        XCTAssertEqual(theme.pulseSpeed, 0)
    }

    func testHighEnergyAboveOneTwentyBPMWithHighFlux() {
        let theme = MoodTheme.from(bpm: 128, energy: 0.8, warmth: 0.1, isPlaying: true)
        XCTAssertEqual(theme.profile, .highEnergy)
        XCTAssertEqual(theme.pulseSpeed, 0.4)
    }

    func testMidEnergyBetweenEightyAndOneTwentyBPM() {
        let theme = MoodTheme.from(bpm: 100, energy: 0.4, warmth: 0.2, isPlaying: true)
        XCTAssertEqual(theme.profile, .midEnergy)
        XCTAssertEqual(theme.pulseSpeed, 0.8)
    }

    func testCalmBelowEightyBPMWithLowWarmth() {
        let theme = MoodTheme.from(bpm: 60, energy: 0.2, warmth: 0.1, isPlaying: true)
        XCTAssertEqual(theme.profile, .calm)
        XCTAssertEqual(theme.pulseSpeed, 1.6)
    }

    func testWorshipBelowEightyBPMWithHighWarmthTakesPriorityOverCalm() {
        let theme = MoodTheme.from(bpm: 65, energy: 0.2, warmth: 0.75, isPlaying: true)
        XCTAssertEqual(theme.profile, .worship)
        XCTAssertEqual(theme.pulseSpeed, 2.4)
    }

    func testHighBPMWithLowFluxFallsThroughToCalm() {
        // BPM > 120 but energy <= 0.55 doesn't qualify for highEnergy, and
        // BPM is outside the 80-120 midEnergy band, so it falls to calm.
        let theme = MoodTheme.from(bpm: 130, energy: 0.3, warmth: 0.1, isPlaying: true)
        XCTAssertEqual(theme.profile, .calm)
    }

    func testShouldUpdateTrueWhenProfileChanges() {
        let calm = MoodTheme.from(bpm: 60, energy: 0.2, warmth: 0.1, isPlaying: true)
        let highEnergy = MoodTheme.from(bpm: 128, energy: 0.8, warmth: 0.1, isPlaying: true)
        XCTAssertTrue(calm.shouldUpdate(to: highEnergy))
    }

    func testShouldUpdateFalseForSmallGlowIntensityChangeWithinThreshold() {
        let a = MoodTheme.from(bpm: 100, energy: 0.4, warmth: 0.2, isPlaying: true)
        let b = MoodTheme.from(bpm: 100, energy: 0.41, warmth: 0.2, isPlaying: true)
        XCTAssertFalse(a.shouldUpdate(to: b))
    }

    func testShouldUpdateTrueWhenGlowIntensityExceedsThreshold() {
        let a = MoodTheme.from(bpm: 100, energy: 0.1, warmth: 0.2, isPlaying: true)
        let b = MoodTheme.from(bpm: 100, energy: 0.9, warmth: 0.2, isPlaying: true)
        XCTAssertTrue(a.shouldUpdate(to: b))
    }
}

import CoreGraphics

/// Shared sizing constants for the island window and its three states.
/// Centralised here so `IslandWindowController` (frame sizing/animation) and
/// the SwiftUI views (layout) never drift out of sync.
enum IslandMetrics {
    /// Height of the physical notch area we render under, on notched
    /// MacBooks (14"/16" M-series). Older non-notch Macs simply render this
    /// as a floating pill near the top of the screen.
    static let notchHeight: CGFloat = 32

    static let collapsedSize = CGSize(width: 340, height: 38)
    static let expandedSize = CGSize(width: 420, height: 150)
    static let fullScreenSize = CGSize(width: 560, height: 340)

    static let cornerRadiusCollapsed: CGFloat = 16
    static let cornerRadiusExpanded: CGFloat = 24

    /// Spring used for collapse/expand transitions.
    static let transition = (response: 0.35, dampingFraction: 0.78)
}

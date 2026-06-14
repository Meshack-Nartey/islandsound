import SwiftUI

/// Root view of the island. Switches between `.collapsed`, `.expanded` and
/// `.fullScreen` based on `appState.islandState`, and owns the hover-to-reveal
/// interaction (collapsed -> expanded on hover, expanded -> collapsed when
/// the pointer leaves, unless the user has clicked into full screen).
struct IslandView: View {
    @ObservedObject var appState: AppState

    /// Debounces the expanded -> collapsed transition so a brief mouse
    /// excursion (e.g. crossing the island to reach a menu) doesn't cause
    /// flicker.
    @State private var collapseTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch appState.islandState {
            case .collapsed:
                CollapsedView(appState: appState)
            case .expanded:
                ExpandedView(appState: appState)
            case .fullScreen:
                FullScreenView(appState: appState)
            }
        }
        .animation(.spring(response: IslandMetrics.transition.response,
                            dampingFraction: IslandMetrics.transition.dampingFraction),
                   value: appState.islandState)
        .onHover { isHovering in
            handleHover(isHovering)
        }
        .fixedSize()
    }

    private func handleHover(_ isHovering: Bool) {
        collapseTask?.cancel()

        switch appState.islandState {
        case .collapsed where isHovering:
            appState.islandState = .expanded

        case .expanded where !isHovering:
            collapseTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                if appState.islandState == .expanded {
                    appState.islandState = .collapsed
                }
            }

        default:
            break
        }
    }
}

#Preview {
    IslandView(appState: .shared)
        .padding()
        .background(Color.gray.opacity(0.2))
}

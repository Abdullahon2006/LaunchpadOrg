import Foundation
import Observation

/// Shared drag state — read synchronously by drop handlers so we don't pay
/// the cost of an NSItemProvider round-trip.
///
/// Drop model:
///   • drop on folder slot              → add app to folder (source becomes empty)
///   • drop on app slot after ≥0.5 s    → create new folder from both
///   • drop on app slot otherwise       → swap the two slots
///   • drop on nil slot                 → swap (source moves there)
@Observable
final class DragState {
    /// Flat slot index the user is dragging from.
    var source: Int?

    /// Flat slot index currently under the pointer.
    var hoverTarget: Int?

    /// Promoted to true once the pointer has dwelt on the same target long
    /// enough that a drop should create a folder instead of reordering.
    var willCreateFolder: Bool = false

    /// App currently being dragged out of an open folder panel (decoupled
    /// from grid drags).
    var draggingOutOfFolder: UUID?

    @ObservationIgnored private var dwellTimer: DispatchWorkItem?

    func scheduleDwell(_ seconds: TimeInterval, action: @escaping () -> Void) {
        dwellTimer?.cancel()
        let work = DispatchWorkItem(block: action)
        dwellTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func cancelDwell() {
        dwellTimer?.cancel()
        dwellTimer = nil
    }

    func clear() {
        source = nil
        hoverTarget = nil
        willCreateFolder = false
        draggingOutOfFolder = nil
        cancelDwell()
    }
}

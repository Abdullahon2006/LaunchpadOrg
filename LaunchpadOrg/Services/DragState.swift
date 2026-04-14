import Foundation
import Observation

/// Shared drag state so the drop handler can read the source synchronously
/// instead of awaiting an `NSItemProvider.loadItem` callback.
///
/// The drop model:
///   - drop on a folder  → always adds the app to the folder
///   - drop on an app after dwelling ≥ 0.5 s → create a new folder
///   - drop on an app otherwise → reorder (source takes target's slot)
@Observable
final class DragState {
    /// Source of the in-flight grid drag — (pageIndex, nodeIndex).
    var source: IndexPath?

    /// Slot the pointer is currently over.
    var hoverTarget: IndexPath?

    /// Promoted to `true` after `source` has hovered the same `hoverTarget`
    /// long enough to mean "merge into folder" rather than "reorder".
    var willCreateFolder: Bool = false

    /// An app currently being dragged out of an open folder sheet (separate
    /// from `source`, which is only for the main grid).
    var draggingOutOfFolder: UUID?

    @ObservationIgnored private var dwellTimer: DispatchWorkItem?

    /// Schedule a work item to run after `seconds`; cancels any prior dwell.
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

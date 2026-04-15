import Foundation
import Observation

/// Which part of a cell the pointer is over during a drag.
enum DropZone {
    case insertBefore   // left third — reorder (insert before the hovered item)
    case insertAfter    // right third — reorder (insert after the hovered item)
    case merge          // center third — on release, create folder / add to folder
}

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

    /// Which zone of the hovered cell the pointer is over. Drives the live
    /// reflow preview (insert opens a gap; merge keeps the layout still and
    /// highlights the target).
    var dropZone: DropZone = .merge

    /// True when the current hover zone would produce a folder on release.
    /// Derived from `dropZone == .merge` and the hovered node's kind, but
    /// cached so views can drive animations off a single flag.
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
        dropZone = .merge
        willCreateFolder = false
        draggingOutOfFolder = nil
        cancelDwell()
    }
}

import Foundation
import AppKit

enum AppLauncher {
    static func launch(_ item: AppItem) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: item.bundleURL, configuration: config) { _, error in
            if let error {
                NSLog("LaunchpadOrg: failed to launch \(item.name): \(error.localizedDescription)")
            }
        }
    }

    static func showInFinder(_ item: AppItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.bundleURL])
    }
}

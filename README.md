# LaunchpadOrg

An open-source SwiftUI clone of macOS Launchpad (and the LaunchOS alternative) for **macOS 26 Tahoe**.

Scans the apps installed on your Mac, arranges them into a paged grid, lets you drag-and-drop to reorder, create custom folders, search, go full-screen, and launch anything with a click.

## Features

- **Real apps** — pulls from `/Applications`, `/System/Applications`, `/Applications/Utilities`, `/System/Applications/Utilities`, and `~/Applications`.
- **Paged grid** — 7×5 icons per page, swipe/tab between pages.
- **Drag-and-drop** — rearrange apps, and drop one onto another to create a folder.
- **Folders** — rename, open in a modal sheet, persist across launches.
- **Search** — instant filtering across every installed app.
- **Full-screen** — `⌘F` toggles full-screen mode.
- **Launches apps** — via `NSWorkspace.openApplication(at:configuration:)`.
- **Persistent layout** — your arrangement is saved to `UserDefaults` as JSON.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26
- Swift 5.9+ (uses `@Observable`)

## Running

```bash
open LaunchpadOrg.xcodeproj
```

Then press **⌘R** in Xcode.

> First-time-only: if you installed Xcode fresh, run `sudo xcodebuild -license accept` once so command-line builds work.

## Architecture

```
LaunchpadOrg/
├── LaunchpadOrgApp.swift     @main, window configuration
├── ContentView.swift         Search bar + paged grid + folder sheet
├── Models/
│   ├── AppItem.swift         Discovered app (id, name, bundleURL)
│   └── AppFolder.swift       LayoutNode enum: .app | .folder
├── Services/
│   ├── AppScanner.swift      Scans /Applications for .app bundles
│   ├── AppLauncher.swift     NSWorkspace launch + "Show in Finder"
│   └── LayoutStore.swift     @Observable, persists layout to UserDefaults
└── Views/
    ├── AppGridView.swift     LazyVGrid + .onDrag/.onDrop + folder creation
    ├── AppIconView.swift     Icon + label, tap to launch, context menu
    ├── FolderView.swift      Folder mini-grid + modal detail sheet
    └── SearchBar.swift       Capsule text field
```

## Notes on Sandboxing

The App Sandbox entitlement is **disabled** (`LaunchpadOrg.entitlements`) because a sandboxed app cannot launch arbitrary third-party apps from `/Applications`. This is acceptable for a developer-run open-source tool, but means the app cannot be submitted to the Mac App Store as-is.

## License

MIT — see [LICENSE](LICENSE).

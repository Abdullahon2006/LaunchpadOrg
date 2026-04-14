import SwiftUI

@main
struct LaunchpadOrgApp: App {
    @State private var layoutStore = LayoutStore()

    var body: some Scene {
        WindowGroup("LaunchpadOrg") {
            ContentView()
                .environment(layoutStore)
                .frame(minWidth: 900, minHeight: 650)
                .background(WindowAccessor())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .windowArrangement) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
        }
    }
}

/// Bridges access to the hosting NSWindow so we can toggle full-screen.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

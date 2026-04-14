import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FolderIconView: View {
    @Environment(LayoutStore.self) private var store
    let folder: AppFolder
    let apps: [AppItem]
    var iconSize: CGFloat = 88
    var isDropTarget: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous)
                    .fill(.white.opacity(isDropTarget ? 0.32 : 0.2))
                    .frame(width: iconSize, height: iconSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous)
                            .stroke(.white.opacity(isDropTarget ? 0.9 : 0.3),
                                    lineWidth: isDropTarget ? 2 : 1)
                    )

                let mini = min(iconSize / 3.5, 26)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: 4), count: 3), spacing: 4) {
                    ForEach(Array(apps.prefix(9).enumerated()), id: \.offset) { _, app in
                        Image(nsImage: store.icon(for: app))
                            .resizable()
                            .frame(width: mini, height: mini)
                    }
                }
                .frame(width: iconSize - 16, height: iconSize - 16)
            }
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            .scaleEffect(isDropTarget ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: isDropTarget)

            Text(folder.name)
                .font(.system(size: max(10, min(13, iconSize * 0.14)), weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .lineLimit(1)
                .frame(width: iconSize + 28)
        }
        .contentShape(Rectangle())
    }
}

/// Non-modal, overlay-style folder panel. Using an overlay instead of a
/// `.sheet` means we control the open/close animation (spring scale +
/// opacity) and a click on the dimmed backdrop dismisses it — closer to
/// native Launchpad.
struct FolderDetailView: View {
    @Environment(LayoutStore.self) private var store
    @Environment(DragState.self) private var drag
    let folder: AppFolder
    let apps: [AppItem]
    @Binding var selectedAppID: UUID?
    var autoFocusName: Bool
    var onRename: (String) -> Void
    var onClose: () -> Void

    @State private var editingName: String
    @FocusState private var nameFocused: Bool
    @State private var removeZoneActive = false

    init(folder: AppFolder,
         apps: [AppItem],
         selectedAppID: Binding<UUID?>,
         autoFocusName: Bool = false,
         onRename: @escaping (String) -> Void,
         onClose: @escaping () -> Void) {
        self.folder = folder
        self.apps = apps
        self._selectedAppID = selectedAppID
        self.autoFocusName = autoFocusName
        self.onRename = onRename
        self.onClose = onClose
        _editingName = State(initialValue: folder.name)
    }

    var body: some View {
        VStack(spacing: 20) {
            TextField("Folder name", text: $editingName)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .focused($nameFocused)
                .onSubmit { commitAndClose() }
                .frame(maxWidth: 320)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 5), spacing: 20) {
                ForEach(apps) { app in
                    AppIconView(
                        item: app,
                        iconSize: 72,
                        selectedAppID: $selectedAppID,
                        onRemoveFromFolder: {
                            store.removeAppFromFolder(folderID: folder.id, appID: app.id)
                        }
                    )
                    .onDrag {
                        drag.draggingOutOfFolder = app.id
                        return NSItemProvider(object: "folder:\(app.id.uuidString)" as NSString)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            removeDropZone
        }
        .padding(36)
        .frame(minWidth: 620, maxWidth: 780, minHeight: 440)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.35))
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        )
        .onAppear {
            if autoFocusName {
                DispatchQueue.main.async { nameFocused = true }
            }
        }
        .onExitCommand(perform: commitAndClose)
    }

    /// Drop zone at the bottom. Dragging an app icon here removes it from
    /// the folder (returning it to the main grid).
    private var removeDropZone: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.forward.app.fill")
            Text("Drag here to remove from folder")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white.opacity(removeZoneActive ? 1.0 : 0.55))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.white.opacity(removeZoneActive ? 0.9 : 0.3))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(removeZoneActive ? 0.12 : 0.03))
                )
        )
        .animation(.easeOut(duration: 0.15), value: removeZoneActive)
        .onDrop(of: [UTType.text], delegate: RemoveFromFolderDropDelegate(
            drag: drag,
            store: store,
            folderID: folder.id,
            active: $removeZoneActive
        ))
    }

    private func commitAndClose() {
        onRename(editingName)
        onClose()
    }
}

/// Drop target for the "remove from folder" zone — reads the dragged app
/// UUID from `DragState.draggingOutOfFolder`.
struct RemoveFromFolderDropDelegate: DropDelegate {
    let drag: DragState
    let store: LayoutStore
    let folderID: UUID
    @Binding var active: Bool

    func dropEntered(info: DropInfo) { active = true }
    func dropExited(info: DropInfo) { active = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            active = false
            drag.draggingOutOfFolder = nil
        }
        guard let appID = drag.draggingOutOfFolder else { return false }
        store.removeAppFromFolder(folderID: folderID, appID: appID)
        return true
    }
}

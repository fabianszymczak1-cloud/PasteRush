import AppKit
import SwiftUI

/// Nearly fullscreen floating preview; arrow keys still navigate via SearchCoordinator.
public final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    public static let shared: PreviewWindowController = {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        let controller = PreviewWindowController(window: panel)
        panel.delegate = controller
        return controller
    }()

    private var hosting: NSHostingView<LargePreviewRoot>?
    private weak var coordinator: SearchCoordinator?
    private var localMonitor: Any?
    private var keyObserver: NSObjectProtocol?

    public var isShowing: Bool { window?.isVisible == true }

    public func toggle(coordinator: SearchCoordinator) {
        if isShowing {
            hide()
        } else {
            show(coordinator: coordinator)
        }
    }

    public func show(coordinator: SearchCoordinator) {
        self.coordinator = coordinator
        guard let item = coordinator.selectedItem else { return }

        let root = LargePreviewRoot(
            coordinator: coordinator,
            clipId: item.id,
            onClose: { [weak self] in self?.hide() }
        )
        let view = NSHostingView(rootView: root)
        hosting = view
        window?.contentView = view

        positionNearlyFullscreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        installKeys()
    }

    public func hide(restoreSearchFocus: Bool = true) {
        removeKeys()
        window?.orderOut(nil)
        hosting = nil
        coordinator = nil
        // Return focus to search instead of dismissing the whole popup.
        if restoreSearchFocus, PopupWindowController.shared.isVisiblePopup {
            PopupWindowController.shared.restoreKeyFocus()
        }
    }

    public func refreshIfNeeded() {
        guard isShowing, let coordinator, let item = coordinator.selectedItem else { return }
        let root = LargePreviewRoot(
            coordinator: coordinator,
            clipId: item.id,
            onClose: { [weak self] in self?.hide() }
        )
        hosting?.rootView = root
    }

    private func positionNearlyFullscreen() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let insetX = visible.width * 0.04
        let insetY = visible.height * 0.04
        let frame = visible.insetBy(dx: insetX, dy: insetY)
        window?.setFrame(frame, display: true)
    }

    private func installKeys() {
        removeKeys()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
        keyObserver = NotificationCenter.default.addObserver(
            forName: .pasteRushHidePopup,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeKeys() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
            self.keyObserver = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if event.keyCode == 53 { // Esc — close preview only, keep search open
            hide()
            return nil
        }
        if event.keyCode == 49 && (flags.isEmpty || flags == .option) {
            hide()
            return nil
        }
        // ↑/← previous, ↓/→ next
        if event.keyCode == 126 || event.keyCode == 123 {
            coordinator?.moveSelection(delta: -1)
            refreshIfNeeded()
            return nil
        }
        if event.keyCode == 125 || event.keyCode == 124 {
            coordinator?.moveSelection(delta: 1)
            refreshIfNeeded()
            return nil
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            if let id = coordinator?.selectedItem?.id {
                if flags.contains(.shift) {
                    PasteCoordinator.shared.paste(clipId: id, plainTextOnly: true)
                } else {
                    PasteCoordinator.shared.paste(clipId: id)
                }
                hide()
            }
            return nil
        }
        return event
    }

    public func windowDidResignKey(_ notification: Notification) {
        // Keep open while browsing; close only on Esc / toggle.
    }
}

struct LargePreviewRoot: View {
    @ObservedObject var coordinator: SearchCoordinator
    let clipId: String
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    if let item = coordinator.selectedItem {
                        Text(metaLine(item))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("preview.close_help"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                PreviewPane(clipId: activeClipId, fillsAvailableSpace: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(2)
    }

    private var activeClipId: String {
        coordinator.selectedItem?.id ?? clipId
    }

    private var title: String {
        coordinator.selectedItem?.displayTitle ?? L10n.tr("preview.title")
    }

    private func metaLine(_ item: ClipListItem) -> String {
        var parts: [String] = [item.primaryType.rawValue]
        if item.primaryType == .image {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(item.totalBytes), countStyle: .file))
        }
        if let app = item.sourceAppName { parts.append(app) }
        parts.append(L10n.tr("preview.hints"))
        return parts.joined(separator: " · ")
    }
}

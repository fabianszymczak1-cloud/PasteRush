import AppKit
import SwiftUI

public final class PopupWindowController: NSWindowController, NSWindowDelegate {
    public static let shared: PopupWindowController = {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        // canJoinAllSpaces + moveToActiveSpace together aborts in AppKit validation
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.hasShadow = true
        let controller = PopupWindowController(window: panel)
        panel.delegate = controller
        controller.configureContent()
        return controller
    }()

    private var searchCoordinator = SearchCoordinator()
    private var localMonitor: Any?
    private var isPinnedOpen = false
    private var hostingView: NSHostingView<PopupRootView>?
    public var isVisiblePopup: Bool { window?.isVisible == true }

    private func configureContent() {
        let root = PopupRootView(coordinator: searchCoordinator, controller: self)
        let hosting = NSHostingView(rootView: root)
        hostingView = hosting
        window?.contentView = hosting

        NotificationCenter.default.addObserver(self, selector: #selector(hide), name: .pasteRushHidePopup, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(toggle), name: .pasteRushTogglePopup, object: nil)
        NotificationCenter.default.addObserver(forName: .pasteRushHistoryDidChange, object: nil, queue: .main) { [weak self] _ in
            if self?.isVisiblePopup == true {
                self?.searchCoordinator.refresh()
            }
        }
    }

    @objc public func toggle() {
        if isVisiblePopup {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        let start = CFAbsoluteTimeGetCurrent()
        PasteCoordinator.shared.previousAppTracker.capture()

        let settings = SettingsStore.shared
        let size = NSSize(width: settings.popupWidth, height: settings.popupHeight)
        var origin = resolveOrigin(size: size, mode: settings.popupPositionMode)
        origin = clampToVisibleScreen(origin: origin, size: size)
        window?.setFrame(NSRect(origin: origin, size: size), display: true)
        window?.alphaValue = CGFloat(settings.popupOpacity)
        window?.level = settings.alwaysOnTop ? .floating : .normal

        searchCoordinator.reset()
        // Make key and order front without activating the app fully if possible
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        installLocalMonitor()
        focusSearchField()

        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if ms > 120 {
            NSLog("PasteRush popup show took %.1fms", ms)
        }
    }

    @objc public func hide() {
        PreviewWindowController.shared.hide(restoreSearchFocus: false)
        if let frame = window?.frame {
            SettingsStore.shared.lastPopupOriginX = frame.origin.x
            SettingsStore.shared.lastPopupOriginY = frame.origin.y
            SettingsStore.shared.popupWidth = frame.size.width
            SettingsStore.shared.popupHeight = frame.size.height
        }
        removeLocalMonitor()
        window?.orderOut(nil)
        isPinnedOpen = false
    }

    public func setPinnedOpen(_ pinned: Bool) {
        isPinnedOpen = pinned
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self.window?.contentView)
            NotificationCenter.default.post(name: .pasteRushFocusSearch, object: nil)
        }
    }

    /// Called when large preview closes so Esc/close returns to search, not dismisses it.
    public func restoreKeyFocus() {
        guard isVisiblePopup else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        focusSearchField()
    }

    private func installLocalMonitor() {
        removeLocalMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    private func removeLocalMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])

        if event.keyCode == 53 { // Escape
            if PreviewWindowController.shared.isShowing {
                PreviewWindowController.shared.hide()
                return nil
            }
            hide()
            return nil
        }
        // ↑/← previous, ↓/→ next (←→ especially useful while large preview is open)
        if event.keyCode == 126 || event.keyCode == 123 {
            searchCoordinator.moveSelection(delta: -1)
            PreviewWindowController.shared.refreshIfNeeded()
            return nil
        }
        if event.keyCode == 125 || event.keyCode == 124 {
            searchCoordinator.moveSelection(delta: 1)
            PreviewWindowController.shared.refreshIfNeeded()
            return nil
        }
        if event.keyCode == 116 { // Page Up
            searchCoordinator.page(delta: -1)
            PreviewWindowController.shared.refreshIfNeeded()
            return nil
        }
        if event.keyCode == 121 { // Page Down
            searchCoordinator.page(delta: 1)
            PreviewWindowController.shared.refreshIfNeeded()
            return nil
        }
        if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            guard let item = searchCoordinator.selectedItem else { return nil }
            if flags.contains(.shift) {
                PasteCoordinator.shared.paste(clipId: item.id, plainTextOnly: true)
            } else if flags.contains(.command) {
                PasteCoordinator.shared.paste(clipId: item.id, copyOnly: true)
            } else if flags.contains(.option) {
                NotificationCenter.default.post(name: .pasteRushShowProperties, object: item.id)
            } else {
                PasteCoordinator.shared.paste(clipId: item.id)
            }
            return nil
        }
        // Backspace: edit search query. Cmd+Backspace / Forward Delete: delete clip.
        if event.keyCode == 51 { // Backspace
            if flags.contains(.command) {
                if let item = searchCoordinator.selectedItem {
                    NotificationCenter.default.post(name: .pasteRushDeleteClip, object: item.id)
                }
                return nil
            }
            if !searchCoordinator.query.isEmpty {
                searchCoordinator.deleteBackward()
                return nil
            }
            // Empty query: do nothing (avoid accidental clip deletion)
            return nil
        }
        if event.keyCode == 117 { // Forward Delete
            if let item = searchCoordinator.selectedItem {
                NotificationCenter.default.post(name: .pasteRushDeleteClip, object: item.id)
            }
            return nil
        }

        // Space: empty query → large preview; otherwise type space. Option+Space always toggles preview.
        if event.keyCode == 49 && flags.isEmpty {
            if searchCoordinator.query.isEmpty {
                PreviewWindowController.shared.toggle(coordinator: searchCoordinator)
            } else {
                searchCoordinator.appendText(" ")
            }
            return nil
        }
        if event.keyCode == 49 && flags == .option {
            PreviewWindowController.shared.toggle(coordinator: searchCoordinator)
            return nil
        }

        if flags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "p" {
            if let item = searchCoordinator.selectedItem {
                let repo = ClipRepository()
                repo.setPinned(id: item.id, pinned: !item.isPinned)
                searchCoordinator.refresh()
            }
            return nil
        }
        if flags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "e" {
            NotificationCenter.default.post(name: .pasteRushEditClip, object: searchCoordinator.selectedItem?.id)
            return nil
        }
        if flags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "g" {
            NotificationCenter.default.post(name: .pasteRushShowGroups, object: nil)
            return nil
        }
        if flags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "," {
            NotificationCenter.default.post(name: .pasteRushOpenSettings, object: nil)
            hide()
            return nil
        }

        // Type-to-search: alphanumeric, Polish chars, punctuation — even if search field lost focus
        if flags.isEmpty || flags == .shift {
            if let chars = event.charactersIgnoringModifiers ?? event.characters, !chars.isEmpty {
                let scalar = chars.unicodeScalars.first!
                if CharacterSet.alphanumerics.contains(scalar) || isPolish(chars) || CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) {
                    searchCoordinator.appendText(chars)
                    return nil
                }
            }
        }

        return event
    }

    private func isPolish(_ s: String) -> Bool {
        let polish = "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"
        return s.contains { polish.contains($0) }
    }

    private func resolveOrigin(size: NSSize, mode: PopupPositionMode) -> NSPoint {
        let settings = SettingsStore.shared
        switch mode {
        case .lastPosition:
            if settings.lastPopupOriginX >= 0, settings.lastPopupOriginY >= 0 {
                return NSPoint(x: settings.lastPopupOriginX, y: settings.lastPopupOriginY)
            }
            fallthrough
        case .mouseCursor:
            let mouse = NSEvent.mouseLocation
            return NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 12)
        case .activeTextField:
            // Best-effort: use mouse as proxy for caret when AX caret unavailable
            let mouse = NSEvent.mouseLocation
            return NSPoint(x: mouse.x, y: mouse.y - size.height - 8)
        }
    }

    private func clampToVisibleScreen(origin: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        var o = origin
        if o.x < visible.minX { o.x = visible.minX + 8 }
        if o.y < visible.minY { o.y = visible.minY + 8 }
        if o.x + size.width > visible.maxX { o.x = visible.maxX - size.width - 8 }
        if o.y + size.height > visible.maxY { o.y = visible.maxY - size.height - 8 }
        return o
    }

    public func windowDidResignKey(_ notification: Notification) {
        // Preview takes key focus while open — don't treat that as leaving the search UI.
        if PreviewWindowController.shared.isShowing { return }
        if SettingsStore.shared.closeOnFocusLoss && !isPinnedOpen && !SettingsStore.shared.keepOpenAfterPaste {
            hide()
        }
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

public extension Notification.Name {
    static let pasteRushFocusSearch = Notification.Name("PasteRushFocusSearch")
    static let pasteRushExternalType = Notification.Name("PasteRushExternalType")
    static let pasteRushTogglePreview = Notification.Name("PasteRushTogglePreview")
    static let pasteRushShowProperties = Notification.Name("PasteRushShowProperties")
    static let pasteRushDeleteClip = Notification.Name("PasteRushDeleteClip")
    static let pasteRushEditClip = Notification.Name("PasteRushEditClip")
    static let pasteRushShowGroups = Notification.Name("PasteRushShowGroups")
    static let pasteRushOpenSettings = Notification.Name("PasteRushOpenSettings")
}

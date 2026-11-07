import SwiftUI
import AppKit
import PasteRushCore
#if !PASTERUSH_APP_STORE
import Sparkle
#endif

@main
struct PasteRushApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {}
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var toastWindow: NSWindow?
    #if !PASTERUSH_APP_STORE
    private var updaterController: SPUStandardUpdaterController?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if PASTERUSH_APP_STORE
        Distribution.isAppStore = true
        Distribution.presentSupport = { TipPresenter.show() }
        TipStore.shared.start()
        #endif
        NSApp.setActivationPolicy(.accessory)

        _ = Database.shared

        ClipboardMonitor.shared.start()
        if SettingsStore.shared.isMonitoringPaused {
            ClipboardMonitor.shared.setPaused(true)
        }

        #if !PASTERUSH_APP_STORE
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif

        setupStatusItem()
        setupHotkey()
        observeNotifications()

        if CommandLine.arguments.contains("--store-demo"),
           Bundle.main.bundleIdentifier == "com.itszymczak.pasterush" {
            StoreDemo.run(openSettings: { [weak self] in self?.presentSettings(section: .about) })
            return
        }

        if !SettingsStore.shared.hasCompletedOnboarding {
            showOnboarding()
        }

        if SettingsStore.shared.launchAtLogin {
            try? LaunchAtLoginService().setEnabled(true)
        }

        if SettingsStore.shared.autoBackupEnabled {
            DispatchQueue.global(qos: .utility).async {
                _ = try? BackupService().createBackup(to: URL(fileURLWithPath: SettingsStore.shared.backupDirectoryPath))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
        GlobalHotkeyManager.shared.unregister()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "PasteRush")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.tr("menu.open_history"), action: #selector(openHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.tr("menu.pause_monitoring"), action: #selector(togglePause), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.tr("menu.new_clip"), action: #selector(newClip), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.tr("menu.pinned_only"), action: #selector(pinnedOnly), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.tr("menu.settings"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L10n.tr("menu.stats"), action: #selector(showStats), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.tr("menu.backup"), action: #selector(runBackup), keyEquivalent: ""))
        #if !PASTERUSH_APP_STORE
        menu.addItem(NSMenuItem(title: L10n.tr("menu.check_updates"), action: #selector(checkForUpdates), keyEquivalent: ""))
        #endif
        let supportTitle = L10n.tr(Distribution.isAppStore ? "menu.support_store" : "menu.support")
        let supportItem = NSMenuItem(title: supportTitle, action: #selector(openSupport), keyEquivalent: "")
        supportItem.image = NSImage(systemSymbolName: Distribution.isAppStore ? "heart.fill" : "cup.and.saucer.fill", accessibilityDescription: supportTitle)?
            .withSymbolConfiguration(.init(paletteColors: [NSColor(srgbRed: 0.72, green: 0.42, blue: 0.05, alpha: 1)]))
        menu.addItem(supportItem)
        #if !PASTERUSH_APP_STORE
        menu.addItem(NSMenuItem.separator())
        let dev = NSMenuItem(title: L10n.tr("menu.developer"), action: nil, keyEquivalent: "")
        let devMenu = NSMenu()
        devMenu.addItem(NSMenuItem(title: L10n.tr("menu.manual_paste_test"), action: #selector(manualPasteTest), keyEquivalent: ""))
        devMenu.addItem(NSMenuItem(title: L10n.tr("menu.run_benchmark"), action: #selector(runBenchmark), keyEquivalent: ""))
        dev.submenu = devMenu
        menu.addItem(dev)
        #endif
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.tr("menu.quit"), action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupHotkey() {
        GlobalHotkeyManager.shared.onHotkey = {
            PopupWindowController.shared.toggle()
        }
        let settings = SettingsStore.shared
        let ok = GlobalHotkeyManager.shared.register(keyCode: settings.openHotkeyKeyCode, modifiers: settings.openHotkeyModifiers)
        if !ok {
            NSLog("PasteRush hotkey conflict: \(GlobalHotkeyManager.shared.lastError ?? "")")
        }
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(forName: .pasteRushOpenSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.openSettings() }
        }
        NotificationCenter.default.addObserver(forName: .pasteRushNeedsPasteManual, object: nil, queue: .main) { [weak self] note in
            let msg = note.object as? String
            Task { @MainActor in
                if let msg { self?.showToast(msg) }
            }
        }
        NotificationCenter.default.addObserver(forName: .pasteRushSettingsDidChange, object: nil, queue: .main) { _ in
            GlobalHotkeyManager.shared.reregisterFromSettings()
        }
    }

    @objc private func openHistory() {
        PopupWindowController.shared.show()
    }

    @objc private func togglePause() {
        ClipboardMonitor.shared.togglePause()
        showToast(ClipboardMonitor.shared.isPaused ? L10n.tr("toast.monitoring_paused") : L10n.tr("toast.monitoring_resumed"))
    }

    @objc private func newClip() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("alert.new_clip_title")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.tr("alert.save"))
        alert.addButton(withTitle: L10n.tr("alert.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            let text = field.stringValue
            guard !text.isEmpty else { return }
            let clip = ClipRecord(
                primaryType: .text,
                searchText: text,
                preview: String(text.prefix(240)),
                contentHash: ContentHasher.hashText(text),
                totalBytes: text.utf8.count,
                sourceAppName: "PasteRush",
                formats: [ClipFormat(uti: "public.utf8-plain-text", inlineData: Data(text.utf8), textContent: text, byteSize: text.utf8.count)]
            )
            _ = ClipRepository().insert(clip)
        }
    }

    @objc private func pinnedOnly() {
        let c = PopupWindowController.shared
        c.show()
        NotificationCenter.default.post(name: .pasteRushShowPopup, object: "pinned")
    }

    @objc private func openSettings() {
        presentSettings(section: .general)
    }

    private func presentSettings(section: SettingsSection) {
        if settingsWindow == nil || section != .general {
            let view = SettingsView(initialSection: section)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = L10n.tr("settings.window_title")
            window.setContentSize(NSSize(width: 860, height: 620))
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showStats() {
        let s = ClipRepository().stats()
        let alert = NSAlert()
        alert.messageText = L10n.tr("alert.stats_title")
        alert.informativeText = L10n.tr(
            "alert.stats_body",
            Int64(s.clipCount),
            ByteCountFormatter.string(fromByteCount: s.databaseBytes, countStyle: .file),
            ByteCountFormatter.string(fromByteCount: s.imageBytes, countStyle: .file),
            ByteCountFormatter.string(fromByteCount: s.freeDiskBytes, countStyle: .file)
        )
        alert.runModal()
    }

    @objc private func runBackup() {
        do {
            let url = try BackupService().createBackup()
            showToast(L10n.tr("toast.backup", url.lastPathComponent))
        } catch {
            showToast(error.localizedDescription)
        }
    }

    #if !PASTERUSH_APP_STORE
    @objc private func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
    #endif

    @objc private func openSupport() {
        Distribution.presentSupport()
    }

    @objc private func manualPasteTest() {
        let marker = PasteCoordinator.shared.runPasteTest()
        showToast(L10n.tr("toast.test_paste", marker))
    }

    @objc private func runBenchmark() {
        showToast(L10n.tr("toast.benchmark_start"))
        Task.detached(priority: .userInitiated) {
            let report = BenchmarkRunner().run()
            await MainActor.run {
                self.showToast(report.summary)
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showOnboarding() {
        let view = OnboardingView { [weak self] in
            self?.onboardingWindow?.close()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "PasteRush"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func showToast(_ message: String) {
        let label = NSTextField(labelWithString: message)
        label.alignment = .center
        label.drawsBackground = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 40))
        label.frame = container.bounds.insetBy(dx: 12, dy: 10)
        container.addSubview(label)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        window.level = .statusBar
        window.contentView = container
        window.hasShadow = true
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: frame.midX - 180, y: frame.minY + 40))
        }
        window.orderFront(nil)
        toastWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.toastWindow?.orderOut(nil)
            self?.toastWindow = nil
        }
    }
}

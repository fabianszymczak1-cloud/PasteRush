import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @State private var selected: SettingsSection = .general
    @State private var stats = ClipRepository().stats()
    @State private var hotkeyConflict: String?
    @State private var recordingHotkey = false
    @State private var excludeInput = ""
    @State private var regexInput = ""
    @State private var statusMessage: String?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selected) { section in
                Text(section.title).tag(section)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            ScrollView {
                detail
                    .padding()
                    .frame(maxWidth: 640, alignment: .leading)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { stats = ClipRepository().stats() }
    }

    @ViewBuilder
    private var detail: some View {
        switch selected {
        case .general:
            section(L10n.tr("settings.section.general")) {
                Toggle(L10n.tr("settings.launch_at_login"), isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, value in
                        do {
                            _ = try LaunchAtLoginService().setEnabled(value)
                            statusMessage = value ? L10n.tr("settings.launch_enabled") : L10n.tr("settings.launch_disabled")
                        } catch {
                            statusMessage = L10n.tr("settings.launch_failed", error.localizedDescription)
                            settings.launchAtLogin = LaunchAtLoginService().isEnabled
                        }
                    }
                Toggle(L10n.tr("settings.pause_monitoring"), isOn: $settings.isMonitoringPaused)
                Toggle(L10n.tr("settings.enable_ocr"), isOn: $settings.enableOCR)
            }
        case .shortcuts:
            section(L10n.tr("settings.section.shortcuts")) {
                HStack(alignment: .center, spacing: 12) {
                    Text(L10n.tr("settings.open_hotkey"))
                    Spacer(minLength: 8)
                    Text(GlobalHotkeyManager.displayString(keyCode: settings.openHotkeyKeyCode, modifiers: settings.openHotkeyModifiers))
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(6)
                        .fixedSize(horizontal: true, vertical: false)
                        .help(GlobalHotkeyManager.displayString(keyCode: settings.openHotkeyKeyCode, modifiers: settings.openHotkeyModifiers))
                    Button(recordingHotkey ? L10n.tr("settings.press_shortcut") : L10n.tr("settings.change")) {
                        recordingHotkey = true
                    }
                    HotkeyRecorder(isRecording: $recordingHotkey) { keyCode, mods in
                        settings.openHotkeyKeyCode = keyCode
                        settings.openHotkeyModifiers = mods
                        let ok = GlobalHotkeyManager.shared.register(keyCode: keyCode, modifiers: mods)
                        hotkeyConflict = ok ? nil : GlobalHotkeyManager.shared.lastError
                        recordingHotkey = false
                    }
                    .frame(width: 0, height: 0)
                }
                if let hotkeyConflict {
                    Text(hotkeyConflict).foregroundStyle(.red)
                }
                Text(L10n.tr("settings.default_hotkey")).font(.caption).foregroundStyle(.secondary)
                Text(L10n.tr("settings.fn_unsupported")).font(.caption).foregroundStyle(.secondary)
            }
        case .popup:
            section(L10n.tr("settings.section.popup")) {
                Picker(L10n.tr("settings.position"), selection: $settings.popupPositionMode) {
                    ForEach(PopupPositionMode.allCases) { Text($0.title).tag($0) }
                }
                Slider(value: $settings.popupWidth, in: 360...900) { Text(L10n.tr("settings.width")) }
                Slider(value: $settings.popupHeight, in: 280...800) { Text(L10n.tr("settings.height")) }
                Slider(value: $settings.popupOpacity, in: 0.7...1.0) { Text(L10n.tr("settings.opacity")) }
                Toggle(L10n.tr("settings.always_on_top"), isOn: $settings.alwaysOnTop)
                Toggle(L10n.tr("settings.keep_open"), isOn: $settings.keepOpenAfterPaste)
                Toggle(L10n.tr("settings.close_on_focus_loss"), isOn: $settings.closeOnFocusLoss)
                Stepper(L10n.tr("settings.list_lines", Int64(settings.listLineCount)), value: $settings.listLineCount, in: 1...5)
                Toggle(L10n.tr("settings.thumbnails"), isOn: $settings.showThumbnails)
                Slider(value: $settings.thumbnailSize, in: 24...72) { Text(L10n.tr("settings.thumbnail_size")) }
                Slider(value: $settings.fontSize, in: 11...18) { Text(L10n.tr("settings.font_size")) }
                Slider(value: $settings.listDensity, in: 0.7...1.5) { Text(L10n.tr("settings.list_density")) }
                Toggle(L10n.tr("settings.show_use_count"), isOn: $settings.showUseCount)
            }
        case .history:
            section(L10n.tr("settings.section.history")) {
                Toggle(L10n.tr("settings.allow_duplicates"), isOn: $settings.allowDuplicates)
                Toggle(L10n.tr("settings.bump_duplicates"), isOn: $settings.bumpDuplicatesToTop)
                Stepper(L10n.tr("settings.max_entries", Int64(settings.maxEntries)), value: $settings.maxEntries, in: 0...1_000_000, step: 1000)
                Stepper(L10n.tr("settings.max_days", Int64(settings.maxAgeDays)), value: $settings.maxAgeDays, in: 0...3650)
                Stepper(L10n.tr("settings.max_images", Int64(settings.maxImageEntries)), value: $settings.maxImageEntries, in: 0...100_000)
                Text(L10n.tr("settings.history_note")).font(.caption).foregroundStyle(.secondary)
            }
        case .dataTypes:
            section(L10n.tr("settings.section.data_types")) {
                Toggle(L10n.tr("settings.capture_text"), isOn: $settings.captureText)
                Toggle(L10n.tr("settings.capture_images"), isOn: $settings.captureImages)
                Toggle(L10n.tr("settings.capture_files"), isOn: $settings.captureFiles)
            }
        case .search:
            section(L10n.tr("settings.section.search")) {
                Toggle(L10n.tr("settings.regex_mode"), isOn: $settings.advancedRegexSearch)
                Text(L10n.tr("settings.search_filters"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .privacy:
            section(L10n.tr("settings.section.privacy")) {
                Toggle(L10n.tr("settings.skip_password_managers"), isOn: $settings.skipPasswordManagers)
                HStack {
                    Text(L10n.tr("settings.private_mode"))
                    ForEach([5, 15, 30, 60], id: \.self) { m in
                        Button(L10n.tr("settings.minutes_short", Int64(m))) {
                            ClipboardMonitor.shared.enablePrivateMode(minutes: m)
                            statusMessage = L10n.tr("settings.private_on", Int64(m))
                        }
                    }
                    Button(L10n.tr("settings.disable")) { ClipboardMonitor.shared.clearPrivateMode() }
                }
                Button(L10n.tr("settings.delete_all_history"), role: .destructive) {
                    ClipRepository().deleteAll()
                    stats = ClipRepository().stats()
                    statusMessage = L10n.tr("settings.history_deleted")
                }
            }
        case .excludedApps:
            section(L10n.tr("settings.section.excluded")) {
                Toggle(L10n.tr("settings.allowed_only"), isOn: $settings.allowedBundleIdsOnly)
                HStack {
                    TextField(L10n.tr("settings.bundle_id"), text: $excludeInput)
                    Button(L10n.tr("settings.add_excluded")) {
                        guard !excludeInput.isEmpty else { return }
                        settings.excludedBundleIds.append(excludeInput)
                        excludeInput = ""
                    }
                }
                ForEach(settings.excludedBundleIds, id: \.self) { id in
                    HStack {
                        Text(id).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(L10n.tr("settings.remove")) {
                            settings.excludedBundleIds.removeAll { $0 == id }
                        }
                    }
                }
                Text(L10n.tr("settings.exclude_regex"))
                HStack {
                    TextField("regex", text: $regexInput)
                    Button(L10n.tr("settings.add")) {
                        guard !regexInput.isEmpty else { return }
                        settings.excludeRegexPatterns.append(regexInput)
                        regexInput = ""
                    }
                }
                ForEach(settings.excludeRegexPatterns, id: \.self) { p in
                    Text(p).font(.system(.caption, design: .monospaced))
                }
            }
        case .groups:
            GroupsView()
        case .database:
            section(L10n.tr("settings.section.database")) {
                LabeledContent(L10n.tr("settings.clips"), value: "\(stats.clipCount)")
                LabeledContent(L10n.tr("settings.database"), value: ByteCountFormatter.string(fromByteCount: stats.databaseBytes, countStyle: .file))
                LabeledContent(L10n.tr("settings.images"), value: ByteCountFormatter.string(fromByteCount: stats.imageBytes, countStyle: .file))
                LabeledContent(L10n.tr("settings.free_space"), value: ByteCountFormatter.string(fromByteCount: stats.freeDiskBytes, countStyle: .file))
                Button(L10n.tr("settings.refresh_stats")) { stats = ClipRepository().stats() }
                Button(L10n.tr("settings.vacuum")) {
                    Database.shared.vacuum()
                    stats = ClipRepository().stats()
                    statusMessage = L10n.tr("settings.vacuum_done")
                }
                Button(L10n.tr("settings.rebuild_fts")) {
                    Database.shared.rebuildFTS()
                    statusMessage = L10n.tr("settings.fts_done")
                }
                Button(L10n.tr("settings.create_backup")) {
                    do {
                        let url = try BackupService().createBackup(to: URL(fileURLWithPath: settings.backupDirectoryPath))
                        statusMessage = L10n.tr("toast.backup", url.lastPathComponent)
                    } catch {
                        statusMessage = error.localizedDescription
                    }
                }
                Toggle(L10n.tr("settings.auto_backup"), isOn: $settings.autoBackupEnabled)
                TextField(L10n.tr("settings.backup_dir"), text: $settings.backupDirectoryPath)
            }
        case .advanced:
            section(L10n.tr("settings.section.advanced")) {
                Button(L10n.tr("settings.run_benchmark")) {
                    Task.detached(priority: .userInitiated) {
                        let report = BenchmarkRunner().run()
                        await MainActor.run { statusMessage = report.summary }
                    }
                }
                Button(L10n.tr("settings.integrity")) {
                    statusMessage = Database.shared.integrityCheck()
                }
                Button(L10n.tr("settings.open_data_dir")) {
                    NSWorkspace.shared.open(AppPaths.applicationSupport)
                }
            }
        case .about:
            section(L10n.tr("settings.section.about")) {
                Text(L10n.tr("app.name")).font(.largeTitle.bold())
                Text(L10n.tr("settings.about_tagline"))
                Text(L10n.tr("settings.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))
                Text(L10n.tr("settings.about_privacy"))
                    .foregroundStyle(.secondary)
                Text(L10n.tr("settings.support_cta"))
                    .padding(.top, 8)
                BuyMeACoffeeButton()
            }
        }

        if let statusMessage {
            Text(statusMessage).foregroundStyle(.secondary).padding(.top, 8)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            content()
        }
    }
}

public enum SettingsSection: String, CaseIterable, Identifiable {
    case general, shortcuts, popup, history, dataTypes, search, privacy, excludedApps, groups, database, advanced, about
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .general: return L10n.tr("settings.section.general")
        case .shortcuts: return L10n.tr("settings.section.shortcuts")
        case .popup: return L10n.tr("settings.section.popup")
        case .history: return L10n.tr("settings.section.history")
        case .dataTypes: return L10n.tr("settings.section.data_types")
        case .search: return L10n.tr("settings.section.search")
        case .privacy: return L10n.tr("settings.section.privacy")
        case .excludedApps: return L10n.tr("settings.section.excluded")
        case .groups: return L10n.tr("settings.section.groups")
        case .database: return L10n.tr("settings.section.database")
        case .advanced: return L10n.tr("settings.section.advanced")
        case .about: return L10n.tr("settings.section.about")
        }
    }
}

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onRecord: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onRecord = onRecord
        return v
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onRecord = onRecord
        if isRecording { nsView.window?.makeFirstResponder(nsView) }
    }

    final class RecorderView: NSView {
        var isRecording = false
        var onRecord: ((UInt32, UInt32) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            guard isRecording else { return }
            let mods = GlobalHotkeyManager.carbonModifiers(from: event.modifierFlags)
            onRecord?(UInt32(event.keyCode), mods)
        }
    }
}

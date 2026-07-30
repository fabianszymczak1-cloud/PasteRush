import SwiftUI
import AppKit

struct PopupRootView: View {
    @ObservedObject var coordinator: SearchCoordinator
    weak var controller: PopupWindowController?
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteId: String?
    @State private var showProperties = false
    @State private var propertiesId: String?
    @State private var showGroups = false
    @State private var editText = ""
    @State private var showEdit = false
    @State private var editingId: String?
    @State private var selectedIds: Set<String> = []
    @State private var toast: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            list
            statusBar
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .padding(1)
        .onAppear {
            searchFocused = true
            coordinator.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteRushFocusSearch)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteRushTogglePreview)) { _ in
            PreviewWindowController.shared.toggle(coordinator: coordinator)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteRushDeleteClip)) { note in
            pendingDeleteId = note.object as? String
            showDeleteConfirm = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteRushShowProperties)) { note in
            propertiesId = note.object as? String
            showProperties = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteRushEditClip)) { note in
            if let id = note.object as? String, let clip = ClipRepository().get(id: id) {
                editingId = id
                editText = clip.formats.first(where: { $0.textContent != nil })?.textContent ?? clip.preview
                showEdit = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteRushShowGroups)) { _ in
            showGroups = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteRushNeedsPasteManual)) { note in
            toast = note.object as? String
        }
        .onChange(of: coordinator.selectedIndex) { _, _ in
            PreviewWindowController.shared.refreshIfNeeded()
        }
        .alert(L10n.tr("alert.delete_clip"), isPresented: $showDeleteConfirm) {
            Button(L10n.tr("alert.delete"), role: .destructive) {
                if let id = pendingDeleteId {
                    ClipRepository().delete(id: id)
                    coordinator.refresh()
                }
            }
            Button(L10n.tr("alert.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showProperties) {
            if let id = propertiesId {
                PropertiesView(clipId: id)
            }
        }
        .sheet(isPresented: $showEdit) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("popup.edit_title")).font(.headline)
                TextEditor(text: $editText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                HStack {
                    Spacer()
                    Button(L10n.tr("alert.cancel")) { showEdit = false }
                    Button(L10n.tr("alert.save")) {
                        if let id = editingId {
                            ClipRepository().updateText(id: id, text: editText)
                            coordinator.refresh()
                        }
                        showEdit = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 480, height: 320)
        }
        .sheet(isPresented: $showGroups) {
            GroupsView()
                .frame(width: 420, height: 360)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .padding(8)
                    .background(.thickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.toast = nil }
                    }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.tr("popup.search"), text: Binding(
                get: { coordinator.query },
                set: { coordinator.search($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: settings.fontSize))
            .focused($searchFocused)
            if coordinator.pinnedOnly {
                Text(L10n.tr("popup.pinned_badge"))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Capsule())
            }
            Button {
                controller?.setPinnedOpen(true)
            } label: {
                Image(systemName: "pin")
            }
            .buttonStyle(.borderless)
            .help(L10n.tr("popup.pin_window"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedIds) {
                ForEach(Array(coordinator.results.enumerated()), id: \.element.id) { index, item in
                    ClipRowView(item: item, isSelected: index == coordinator.selectedIndex, query: coordinator.query)
                        .tag(item.id)
                        .listRowInsets(EdgeInsets(top: 2 * settings.listDensity, leading: 8, bottom: 2 * settings.listDensity, trailing: 8))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            PasteCoordinator.shared.paste(clipId: item.id)
                        }
                        .onTapGesture {
                            coordinator.selectedIndex = index
                        }
                        .id(item.id)
                        .contextMenu {
                            Button(L10n.tr("popup.paste")) { PasteCoordinator.shared.paste(clipId: item.id) }
                            Button(L10n.tr("popup.paste_plain")) { PasteCoordinator.shared.paste(clipId: item.id, plainTextOnly: true) }
                            Button(L10n.tr("popup.copy_only")) { PasteCoordinator.shared.paste(clipId: item.id, copyOnly: true) }
                            Menu(L10n.tr("popup.paste_special")) {
                                ForEach(TextTransform.allCases) { t in
                                    Button(t.title) {
                                        PasteCoordinator.shared.paste(clipId: item.id, transform: t)
                                    }
                                }
                            }
                            Divider()
                            Button(item.isPinned ? L10n.tr("popup.unpin") : L10n.tr("popup.pin")) {
                                ClipRepository().setPinned(id: item.id, pinned: !item.isPinned)
                                coordinator.refresh()
                            }
                            Button(item.neverDelete ? L10n.tr("popup.never_delete_off") : L10n.tr("popup.never_delete_on")) {
                                ClipRepository().setNeverDelete(id: item.id, value: !item.neverDelete)
                                coordinator.refresh()
                            }
                            Button(L10n.tr("alert.delete"), role: .destructive) {
                                pendingDeleteId = item.id
                                showDeleteConfirm = true
                            }
                        }
                }
            }
            .listStyle(.plain)
            .id(coordinator.listSessionID)
            .onChange(of: coordinator.selectedIndex) { _, newValue in
                if coordinator.results.indices.contains(newValue) {
                    proxy.scrollTo(coordinator.results[newValue].id, anchor: .center)
                }
            }
            .onChange(of: coordinator.listSessionID) { _, _ in
                scrollListToTop(proxy: proxy)
            }
        }
    }

    private func scrollListToTop(proxy: ScrollViewProxy) {
        guard let first = coordinator.results.first else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(first.id, anchor: .top)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(L10n.tr("popup.results", Int64(coordinator.results.count)))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if !selectedIds.isEmpty {
                Menu(L10n.tr("popup.selection", Int64(selectedIds.count))) {
                    Button(L10n.tr("popup.paste_sequential")) {
                        PasteCoordinator.shared.pasteMultiple(ids: Array(selectedIds), mode: .sequential)
                    }
                    Button(L10n.tr("popup.join_newline")) {
                        PasteCoordinator.shared.pasteMultiple(ids: Array(selectedIds), mode: .newline)
                    }
                    Button(L10n.tr("popup.join_space")) {
                        PasteCoordinator.shared.pasteMultiple(ids: Array(selectedIds), mode: .space)
                    }
                    Button(L10n.tr("popup.join_comma")) {
                        PasteCoordinator.shared.pasteMultiple(ids: Array(selectedIds), mode: .comma)
                    }
                }
                .font(.caption)
            }
            Text(L10n.tr("popup.hints"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct ClipRowView: View {
    let item: ClipListItem
    let isSelected: Bool
    let query: String
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 8) {
            if settings.showThumbnails {
                thumbnail
                    .frame(width: settings.thumbnailSize, height: settings.thumbnailSize)
            }
            VStack(alignment: .leading, spacing: 2) {
                highlightedText
                    .lineLimit(settings.listLineCount)
                    .font(.system(size: settings.fontSize))
                HStack(spacing: 6) {
                    if item.isPinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    if let group = item.groupName {
                        Text(group).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let app = item.sourceAppName {
                        Text(app).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(RelativeTimeFormatter.string(from: item.copiedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if settings.showUseCount, item.useCount > 0 {
                        Text("×\(item.useCount)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            typeIcon
        }
        .padding(.vertical, 2)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var highlightedText: Text {
        let source = item.displayTitle
        let q = query.split(whereSeparator: { $0.isWhitespace }).map(String.init).first ?? ""
        guard !q.isEmpty, let range = source.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(source)
        }
        var attributed = AttributedString(source)
        if let attrRange = Range(range, in: attributed) {
            attributed[attrRange].backgroundColor = .yellow.opacity(0.45)
        }
        return Text(attributed)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if item.primaryType == .image, let path = item.thumbnailPath, let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).clipped().cornerRadius(4)
        } else {
            Image(systemName: iconName)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(4)
        }
    }

    private var typeIcon: some View {
        Image(systemName: iconName)
            .foregroundStyle(.secondary)
            .font(.caption)
    }

    private var iconName: String {
        switch item.primaryType {
        case .image: return "photo"
        case .url: return "link"
        case .file: return "doc"
        case .html, .rtf: return "doc.richtext"
        case .color: return "paintpalette"
        default: return "doc.plaintext"
        }
    }
}

enum RelativeTimeFormatter {
    static func string(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "przed chwilą" }
        if seconds < 3600 { return "\(seconds / 60) min temu" }
        if seconds < 86400 { return "\(seconds / 3600) godz. temu" }
        if seconds < 86400 * 7 { return "\(seconds / 86400) dn. temu" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

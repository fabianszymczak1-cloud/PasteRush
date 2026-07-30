import SwiftUI
import AppKit

struct PreviewPane: View {
    let clipId: String
    var fillsAvailableSpace: Bool = false
    @State private var clip: ClipRecord?
    @State private var mode: PreviewMode = .formatted

    enum PreviewMode: String, CaseIterable {
        case formatted = "Podgląd"
        case plain = "Tekst"
        case meta = "Metadane"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !fillsAvailableSpace || clip?.primaryType != .image {
                Picker("", selection: $mode) {
                    ForEach(PreviewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
            }

            Group {
                switch mode {
                case .formatted:
                    formattedPreview
                case .plain:
                    ScrollView {
                        Text(plainText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(fillsAvailableSpace ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                case .meta:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            metaRow("ID", clip?.id ?? "")
                            metaRow("Typ", clip?.primaryType.rawValue ?? "")
                            metaRow("Hash", clip?.contentHash ?? "")
                            metaRow("Rozmiar", ByteCountFormatter.string(fromByteCount: Int64(clip?.totalBytes ?? 0), countStyle: .file))
                            metaRow("Aplikacja", clip?.sourceAppName ?? "—")
                            metaRow("Bundle", clip?.sourceBundleId ?? "—")
                            metaRow("Użycia", "\(clip?.useCount ?? 0)")
                            if let w = clip?.imageWidth, let h = clip?.imageHeight {
                                metaRow("Rozdzielczość", "\(w)×\(h)")
                            }
                            Text("Formaty:").font(.caption).bold()
                                .foregroundStyle(fillsAvailableSpace ? Color.white.opacity(0.8) : Color.primary)
                            ForEach(clip?.formats ?? [], id: \.uti) { f in
                                Text("• \(f.uti) (\(ByteCountFormatter.string(fromByteCount: Int64(f.byteSize), countStyle: .file)))")
                                    .font(.caption2)
                                    .foregroundStyle(fillsAvailableSpace ? Color.white.opacity(0.7) : Color.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(fillsAvailableSpace ? 4 : 8)
        .onAppear {
            clip = ClipRepository().get(id: clipId)
            if clip?.primaryType == .image { mode = .formatted }
        }
        .onChange(of: clipId) { _, newId in
            clip = ClipRepository().get(id: newId)
            if clip?.primaryType == .image { mode = .formatted }
        }
    }

    private var plainText: String {
        clip?.formats.first(where: { $0.textContent != nil })?.textContent ?? clip?.searchText ?? clip?.preview ?? ""
    }

    @ViewBuilder
    private var formattedPreview: some View {
        if clip?.primaryType == .image {
            if let data = imageData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(fillsAvailableSpace ? 0.35 : 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text("Brak obrazu")
                    .foregroundStyle(fillsAvailableSpace ? Color.white : Color.primary)
            }
        } else if clip?.primaryType == .html, let html = clip?.formats.first(where: { $0.uti.contains("html") })?.textContent ?? clip?.formats.first(where: { $0.uti.contains("html") })?.inlineData.flatMap({ String(data: $0, encoding: .utf8) }) {
            HTMLPreview(html: html)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                Text(plainText)
                    .font(.system(size: fillsAvailableSpace ? 18 : 14))
                    .foregroundStyle(fillsAvailableSpace ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(fillsAvailableSpace ? 24 : 0)
            }
        }
    }

    private var imageData: Data? {
        guard let clip else { return nil }
        for f in clip.formats where f.uti.contains("png") || f.uti.contains("tiff") || f.uti.contains("image") {
            if let d = f.inlineData { return d }
            if let p = f.blobPath { return try? Data(contentsOf: URL(fileURLWithPath: p)) }
        }
        return nil
    }

    private func metaRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k)
                .font(.caption)
                .foregroundStyle(fillsAvailableSpace ? Color.white.opacity(0.6) : Color.secondary)
                .frame(width: 100, alignment: .leading)
            Text(v)
                .font(.caption)
                .foregroundStyle(fillsAvailableSpace ? Color.white : Color.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

struct HTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let tv = NSTextView()
        tv.isEditable = false
        if let data = html.data(using: .utf8),
           let attr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
           ) {
            tv.textStorage?.setAttributedString(attr)
        } else {
            tv.string = html
        }
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

struct PropertiesView: View {
    let clipId: String
    @Environment(\.dismiss) private var dismiss
    @State private var clip: ClipRecord?
    @State private var customName = ""
    @State private var neverDelete = false
    @State private var pinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Właściwości").font(.title2.bold())
            TextField("Własna nazwa", text: $customName)
            Toggle("Przypięty", isOn: $pinned)
            Toggle("Nigdy nie usuwaj", isOn: $neverDelete)
            if let clip {
                PreviewPane(clipId: clip.id).frame(minHeight: 200)
            }
            HStack {
                Spacer()
                Button("Zamknij") { dismiss() }
                Button("Zapisz") {
                    let repo = ClipRepository()
                    if let clip {
                        repo.setPinned(id: clip.id, pinned: pinned)
                        repo.setNeverDelete(id: clip.id, value: neverDelete)
                        if !customName.isEmpty {
                            Database.shared.exec("UPDATE clips SET custom_name = '\(customName.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(clip.id)';")
                        }
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520, height: 480)
        .onAppear {
            clip = ClipRepository().get(id: clipId)
            customName = clip?.customName ?? ""
            neverDelete = clip?.neverDelete ?? false
            pinned = clip?.isPinned ?? false
        }
    }
}

struct GroupsView: View {
    @State private var groups: [ClipGroup] = []
    @State private var newName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grupy").font(.title2.bold())
            List {
                ForEach(groups) { group in
                    HStack {
                        Text(group.name)
                        Spacer()
                        Button("Usuń", role: .destructive) {
                            ClipRepository().deleteGroup(id: group.id)
                            reload()
                        }
                    }
                }
            }
            HStack {
                TextField("Nowa grupa", text: $newName)
                Button("Dodaj") {
                    guard !newName.isEmpty else { return }
                    ClipRepository().createGroup(ClipGroup(name: newName, sortOrder: groups.count))
                    newName = ""
                    reload()
                }
            }
            Button("Zamknij") { dismiss() }
        }
        .padding()
        .onAppear(perform: reload)
    }

    private func reload() {
        groups = ClipRepository().allGroups()
    }
}

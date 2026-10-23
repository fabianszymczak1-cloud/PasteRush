import AppKit
import PasteRushCore

/// Sample history for App Store screenshots and the review recording.
/// Runs only inside the sandboxed store build, so it cannot touch the GitHub app's database.
enum StoreDemo {
    static func run(openSettings: @escaping () -> Void) {
        let settings = SettingsStore.shared
        settings.hasCompletedOnboarding = true
        settings.showThumbnails = true
        settings.thumbnailSize = 72.0
        settings.popupWidth = 960
        settings.popupHeight = 560
        settings.popupOpacity = 1
        settings.listLineCount = 2
        settings.fontSize = 14.0
        settings.popupPositionMode = .lastPosition
        settings.closeOnFocusLoss = false
        settings.keepOpenAfterPaste = true
        settings.alwaysOnTop = true
        if let screen = NSScreen.main?.visibleFrame {
            settings.lastPopupOriginX = screen.midX - 480
            settings.lastPopupOriginY = screen.midY - 180
        }

        let repo = ClipRepository()
        repo.deleteAll()
        seed(repo)

        let mode = CommandLine.arguments.drop(while: { $0 != "--store-demo" }).dropFirst().first ?? "tour"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            switch mode {
            case "settings":
                openSettings()
            case "preview":
                PopupWindowController.shared.show()
                PopupWindowController.shared.setPinnedOpen(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    PopupWindowController.shared.demoPreviewFirstImage()
                }
            case "history":
                PopupWindowController.shared.show()
                PopupWindowController.shared.setPinnedOpen(true)
            default:
                playTour(openSettings: openSettings)
            }
        }
    }

    private static func playTour(openSettings: @escaping () -> Void) {
        let popup = PopupWindowController.shared
        popup.show()
        popup.setPinnedOpen(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            popup.demoSearch("screenshot")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.6) {
            popup.demoPreviewFirstImage()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.6) {
            popup.demoHidePreview()
            popup.hide()
            openSettings()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 14.2) {
            NSApp.terminate(nil)
        }
    }

    private static func seed(_ repo: ClipRepository) {
        let now = Date()
        insertText(
            repo,
            """
            Studio Wi-Fi
            Name: Northlight
            Password stays on this Mac.
            """,
            preview: "Studio Wi-Fi — Northlight",
            app: "Notes",
            copiedAt: now.addingTimeInterval(-20),
            pinned: true
        )
        insertImage(repo, image: coastImage(), title: "Coast at sunset", app: "Preview", copiedAt: now.addingTimeInterval(-80))
        insertText(
            repo,
            """
            func searchHistory() {
                clips.filter { $0.kind == .image }
            }
            """,
            preview: "func searchHistory() { clips.filter { $0.kind == .image } }",
            app: "Xcode",
            copiedAt: now.addingTimeInterval(-140)
        )
        insertText(
            repo,
            "https://developer.apple.com/documentation/appkit",
            preview: "https://developer.apple.com/documentation/appkit",
            app: "Safari",
            copiedAt: now.addingTimeInterval(-200)
        )
        insertImage(repo, image: dashboardImage(), title: "Weekly report screenshot", app: "Safari", copiedAt: now.addingTimeInterval(-260))
        insertText(
            repo,
            """
            Ship notes
            PasteRush keeps screenshots, photos, files, and text.
            The Mac clipboard keeps one item. This list does not.
            """,
            preview: "Ship notes — screenshots, photos, files, and text",
            app: "Notes",
            copiedAt: now.addingTimeInterval(-320)
        )
    }

    private static func insertText(
        _ repo: ClipRepository,
        _ text: String,
        preview: String,
        app: String,
        copiedAt: Date,
        pinned: Bool = false
    ) {
        let data = Data(text.utf8)
        let clip = ClipRecord(
            copiedAt: copiedAt,
            lastUsedAt: copiedAt,
            primaryType: text.hasPrefix("http") ? .url : .text,
            searchText: PolishNormalizer.searchBlob(from: text),
            preview: preview,
            contentHash: ContentHasher.hashText(text),
            totalBytes: data.count,
            sourceAppName: app,
            isPinned: pinned,
            formats: [ClipFormat(uti: "public.utf8-plain-text", inlineData: data, textContent: text, byteSize: data.count)]
        )
        let saved = repo.insert(clip, allowDuplicates: true)
        if pinned {
            repo.setPinned(id: saved.id, pinned: true)
        }
    }

    private static func insertImage(_ repo: ClipRepository, image: NSImage, title: String, app: String, copiedAt: Date) {
        guard let png = pngData(image) else { return }
        let id = UUID().uuidString
        let blob = AppPaths.blobURL(clipId: id, uti: "public.png")
        try? png.write(to: blob, options: .atomic)
        let thumb = AppPaths.thumbnailURL(clipId: id)
        if let jpeg = jpegData(image, max: 160) {
            try? jpeg.write(to: thumb, options: .atomic)
        }
        let clip = ClipRecord(
            id: id,
            copiedAt: copiedAt,
            lastUsedAt: copiedAt,
            primaryType: .image,
            searchText: PolishNormalizer.searchBlob(from: title),
            preview: title,
            contentHash: ContentHasher.hash(formats: [("public.png", png)]),
            totalBytes: png.count,
            sourceAppName: app,
            thumbnailPath: thumb.path,
            imageWidth: Int(image.size.width),
            imageHeight: Int(image.size.height),
            formats: [ClipFormat(uti: "public.png", blobPath: blob.path, byteSize: png.count)]
        )
        _ = repo.insert(clip, allowDuplicates: true)
    }

    private static func dashboardImage() -> NSImage {
        let size = NSSize(width: 880, height: 520)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let card = NSRect(x: 36, y: 36, width: 808, height: 448)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18).fill()
        let title = "Weekly report" as NSString
        title.draw(at: NSPoint(x: 64, y: 420), withAttributes: [
            .font: NSFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
        ])
        let bars: [(CGFloat, NSColor)] = [
            (120, NSColor.systemBlue),
            (180, NSColor.systemTeal),
            (90, NSColor.systemIndigo),
            (210, NSColor.systemBlue),
            (150, NSColor.systemTeal),
            (240, NSColor.systemOrange)
        ]
        for (index, bar) in bars.enumerated() {
            let x = 80 + CGFloat(index) * 120
            let rect = NSRect(x: x, y: 90, width: 64, height: bar.0)
            bar.1.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        }
        image.unlockFocus()
        return image
    }

    private static func coastImage() -> NSImage {
        let size = NSSize(width: 880, height: 520)
        let image = NSImage(size: size)
        image.lockFocus()
        let sky = NSGradient(colors: [
            NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.32, alpha: 1),
            NSColor(calibratedRed: 0.45, green: 0.28, blue: 0.62, alpha: 1)
        ])
        sky?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.34, alpha: 1).setFill()
        let sea = NSBezierPath()
        sea.move(to: NSPoint(x: 0, y: 180))
        sea.curve(to: NSPoint(x: 880, y: 150), controlPoint1: NSPoint(x: 280, y: 230), controlPoint2: NSPoint(x: 560, y: 90))
        sea.line(to: NSPoint(x: 880, y: 0))
        sea.line(to: NSPoint(x: 0, y: 0))
        sea.close()
        sea.fill()
        NSColor(calibratedRed: 1, green: 0.82, blue: 0.45, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 620, y: 340, width: 90, height: 90)).fill()
        image.unlockFocus()
        return image
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func jpegData(_ image: NSImage, max: CGFloat) -> Data? {
        let thumb = NSImage(size: NSSize(width: max, height: max))
        thumb.lockFocus()
        let ratio = min(max / image.size.width, max / image.size.height)
        let draw = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let origin = NSPoint(x: (max - draw.width) / 2, y: (max - draw.height) / 2)
        image.draw(in: NSRect(origin: origin, size: draw))
        thumb.unlockFocus()
        guard let tiff = thumb.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}

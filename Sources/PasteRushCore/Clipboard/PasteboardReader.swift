import AppKit
import Foundation
import UniformTypeIdentifiers

public struct PasteboardSnapshot: Sendable {
    public var changeCount: Int
    public var formats: [(uti: String, data: Data)]
    public var plainText: String?
    public var html: String?
    public var rtf: Data?
    public var urls: [URL]
    public var fileURLs: [URL]
    public var imageData: Data?
    public var imageUTI: String?
    public var imageSize: CGSize?
    public var color: NSColor?
    public var primaryType: ClipPrimaryType
    public var preview: String
    public var searchText: String
    public var contentHash: String
    public var totalBytes: Int
}

public final class PasteboardReader {
    public init() {}

    public func read(pasteboard: NSPasteboard = .general) -> PasteboardSnapshot? {
        let changeCount = pasteboard.changeCount
        var formatPairs: [(uti: String, data: Data)] = []
        var plainText: String?
        var html: String?
        var rtf: Data?
        var urls: [URL] = []
        var fileURLs: [URL] = []
        var imageData: Data?
        var imageUTI: String?
        var imageSize: CGSize?
        var color: NSColor?
        var primary: ClipPrimaryType = .unknown
        var preview = ""
        var searchParts: [String] = []

        let types = pasteboard.types ?? []

        if let str = pasteboard.string(forType: .string), !str.isEmpty {
            plainText = str
            if let data = str.data(using: .utf8) {
                formatPairs.append((UTType.utf8PlainText.identifier, data))
            }
            primary = .text
            preview = String(str.prefix(240)).replacingOccurrences(of: "\n", with: " ")
            searchParts.append(str)
        }

        if let rtfData = pasteboard.data(forType: .rtf), !rtfData.isEmpty {
            rtf = rtfData
            formatPairs.append((UTType.rtf.identifier, rtfData))
            if primary == .unknown { primary = .rtf }
            if plainText == nil, let attr = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
                plainText = attr.string
                preview = String(attr.string.prefix(240)).replacingOccurrences(of: "\n", with: " ")
                searchParts.append(attr.string)
            }
        }

        if let htmlData = pasteboard.data(forType: .html), !htmlData.isEmpty {
            html = String(data: htmlData, encoding: .utf8)
            formatPairs.append((UTType.html.identifier, htmlData))
            if primary == .unknown { primary = .html }
            if let html, searchParts.isEmpty { searchParts.append(html.strippingTags()) }
        }

        if let items = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: false
        ]) as? [URL], !items.isEmpty {
            let files = items.filter { $0.isFileURL }
            let web = items.filter { !$0.isFileURL }
            if !files.isEmpty {
                fileURLs = files
                primary = .file
                let names = files.map(\.lastPathComponent).joined(separator: ", ")
                preview = names
                searchParts.append(names)
                searchParts.append(contentsOf: files.map(\.path))
                if let data = try? NSKeyedArchiver.archivedData(withRootObject: files as NSArray, requiringSecureCoding: false) {
                    formatPairs.append(("public.file-url", data))
                }
            }
            if !web.isEmpty {
                urls = web
                if primary == .unknown || primary == .text { primary = .url }
                let joined = web.map(\.absoluteString).joined(separator: "\n")
                if preview.isEmpty { preview = joined }
                searchParts.append(joined)
                if let data = joined.data(using: .utf8) {
                    formatPairs.append((UTType.url.identifier, data))
                }
            }
        }

        if let png = pasteboard.data(forType: .png), !png.isEmpty {
            imageData = png
            imageUTI = UTType.png.identifier
            formatPairs.append((UTType.png.identifier, png))
            primary = .image
            if let rep = NSBitmapImageRep(data: png) {
                imageSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            }
            if preview.isEmpty { preview = "Image PNG \(Int(imageSize?.width ?? 0))×\(Int(imageSize?.height ?? 0))" }
        } else if let tiff = pasteboard.data(forType: .tiff), !tiff.isEmpty {
            imageData = tiff
            imageUTI = UTType.tiff.identifier
            formatPairs.append((UTType.tiff.identifier, tiff))
            primary = .image
            if let rep = NSBitmapImageRep(data: tiff) {
                imageSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            }
            if preview.isEmpty { preview = "Image TIFF \(Int(imageSize?.width ?? 0))×\(Int(imageSize?.height ?? 0))" }
        } else if let img = NSImage(pasteboard: pasteboard),
                  let tiff = img.tiffRepresentation {
            imageData = tiff
            imageUTI = UTType.tiff.identifier
            formatPairs.append((UTType.tiff.identifier, tiff))
            primary = .image
            imageSize = img.size
            if preview.isEmpty { preview = "Image \(Int(img.size.width))×\(Int(img.size.height))" }
        }

        if types.contains(.color), let colors = pasteboard.readObjects(forClasses: [NSColor.self]) as? [NSColor], let first = colors.first {
            color = first
            if primary == .unknown {
                primary = .color
                preview = first.previewString
            }
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: first, requiringSecureCoding: false) {
                formatPairs.append(("com.apple.cocoa.pasteboard.color", data))
            }
        }

        // Capture any additional typed data not already stored
        for type in types {
            let uti = type.rawValue
            if formatPairs.contains(where: { $0.uti == uti }) { continue }
            if let data = pasteboard.data(forType: type), !data.isEmpty, data.count < 25_000_000 {
                formatPairs.append((uti, data))
            }
        }

        guard !formatPairs.isEmpty else { return nil }

        let hash = ContentHasher.hash(formats: formatPairs)
        let total = formatPairs.reduce(0) { $0 + $1.data.count }
        let searchText = searchParts.joined(separator: "\n")

        return PasteboardSnapshot(
            changeCount: changeCount,
            formats: formatPairs,
            plainText: plainText,
            html: html,
            rtf: rtf,
            urls: urls,
            fileURLs: fileURLs,
            imageData: imageData,
            imageUTI: imageUTI,
            imageSize: imageSize,
            color: color,
            primaryType: primary == .unknown ? .text : primary,
            preview: preview.isEmpty ? "Clipboard item" : preview,
            searchText: searchText,
            contentHash: hash,
            totalBytes: total
        )
    }
}

private extension String {
    func strippingTags() -> String {
        replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension NSColor {
    var previewString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "Color" }
        return String(format: "Color #%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}

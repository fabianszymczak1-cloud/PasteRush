import Foundation
import AppKit

public enum TextTransform: String, CaseIterable, Identifiable, Sendable {
    case plainText
    case uppercased
    case lowercased
    case capitalizedWords
    case sentenceCase
    case invertCase
    case trim
    case removeNewlines
    case newlinesToSpaces
    case camelCase
    case snakeCase
    case kebabCase
    case slug
    case windowsToPosix
    case appendNewline
    case appendTwoNewlines
    case appendDateTime
    case generateUUID
    case textAsImage

    public var id: String { rawValue }

    public var title: String {
        L10n.tr("transform.\(rawValue)")
    }

    public func apply(to text: String) -> String {
        switch self {
        case .plainText: return text
        case .uppercased: return text.uppercased()
        case .lowercased: return text.lowercased()
        case .capitalizedWords: return text.capitalized
        case .sentenceCase:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = trimmed.first else { return text }
            return String(first).uppercased() + trimmed.dropFirst().lowercased()
        case .invertCase:
            return String(text.map { ch in
                if ch.isUppercase { return Character(ch.lowercased()) }
                if ch.isLowercase { return Character(ch.uppercased()) }
                return ch
            })
        case .trim: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .removeNewlines: return text.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        case .newlinesToSpaces: return text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        case .camelCase:
            let parts = text.split{ !$0.isLetter && !$0.isNumber }.map(String.init)
            guard let first = parts.first?.lowercased() else { return text }
            return first + parts.dropFirst().map { $0.capitalized }.joined()
        case .snakeCase:
            return text.split{ !$0.isLetter && !$0.isNumber }.map { $0.lowercased() }.joined(separator: "_")
        case .kebabCase:
            return text.split{ !$0.isLetter && !$0.isNumber }.map { $0.lowercased() }.joined(separator: "-")
        case .slug:
            let folded = PolishNormalizer.fold(text).lowercased()
            let scalars = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            return String(scalars)
                .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        case .windowsToPosix:
            var t = text.replacingOccurrences(of: "\\", with: "/")
            if t.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) != nil {
                let drive = t.prefix(1).lowercased()
                t = "/mnt/\(drive)" + t.dropFirst(2)
            }
            return t
        case .appendNewline: return text + "\n"
        case .appendTwoNewlines: return text + "\n\n"
        case .appendDateTime:
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .medium
            return text + f.string(from: Date())
        case .generateUUID: return UUID().uuidString
        case .textAsImage: return text
        }
    }
}

public enum MultiJoinMode: String, CaseIterable, Identifiable {
    case sequential
    case newline
    case space
    case comma
    case custom
    case imagesVertical
    case imagesHorizontal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sequential: return "Po kolei"
        case .newline: return "Nowa linia"
        case .space: return "Spacja"
        case .comma: return "Przecinek"
        case .custom: return "Własny separator"
        case .imagesVertical: return "Obrazy pionowo"
        case .imagesHorizontal: return "Obrazy poziomo"
        }
    }
}

public enum TextTransforms {
    public static func join(_ texts: [String], mode: MultiJoinMode, customSeparator: String = " | ") -> String {
        switch mode {
        case .sequential, .newline: return texts.joined(separator: "\n")
        case .space: return texts.joined(separator: " ")
        case .comma: return texts.joined(separator: ", ")
        case .custom: return texts.joined(separator: customSeparator)
        case .imagesVertical, .imagesHorizontal: return texts.joined(separator: "\n")
        }
    }

    public static func combineImages(_ images: [NSImage], vertical: Bool) -> NSImage? {
        guard !images.isEmpty else { return nil }
        if vertical {
            let width = images.map(\.size.width).max() ?? 0
            let height = images.map(\.size.height).reduce(0, +)
            let result = NSImage(size: NSSize(width: width, height: height))
            result.lockFocus()
            var y = height
            for image in images {
                y -= image.size.height
                image.draw(in: NSRect(x: 0, y: y, width: image.size.width, height: image.size.height))
            }
            result.unlockFocus()
            return result
        } else {
            let width = images.map(\.size.width).reduce(0, +)
            let height = images.map(\.size.height).max() ?? 0
            let result = NSImage(size: NSSize(width: width, height: height))
            result.lockFocus()
            var x: CGFloat = 0
            for image in images {
                image.draw(in: NSRect(x: x, y: 0, width: image.size.width, height: image.size.height))
                x += image.size.width
            }
            result.unlockFocus()
            return result
        }
    }
}

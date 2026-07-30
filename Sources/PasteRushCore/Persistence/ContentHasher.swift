import Foundation
import CryptoKit

public enum ContentHasher {
    public static func hash(formats: [(uti: String, data: Data)]) -> String {
        var hasher = SHA256()
        let sorted = formats.sorted { $0.uti < $1.uti }
        for item in sorted {
            hasher.update(data: Data(item.uti.utf8))
            hasher.update(data: item.data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func hashText(_ text: String) -> String {
        hash(formats: [("public.utf8-plain-text", Data(text.utf8))])
    }
}

public enum PolishNormalizer {
    private static let map: [Character: Character] = [
        "ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n", "ó": "o", "ś": "s", "ź": "z", "ż": "z",
        "Ą": "A", "Ć": "C", "Ę": "E", "Ł": "L", "Ń": "N", "Ó": "O", "Ś": "S", "Ź": "Z", "Ż": "Z"
    ]

    public static func fold(_ input: String) -> String {
        String(input.map { map[$0] ?? $0 })
    }

    public static func searchBlob(from text: String) -> String {
        let folded = fold(text)
        if folded == text { return text }
        return text + "\n" + folded
    }
}

import Foundation
import AppKit

public struct BenchmarkReport: Sendable {
    public var insertTextMs: Double
    public var searchMs: Double
    public var recentMs: Double
    public var totalClips: Int
    public var summary: String
}

public final class BenchmarkRunner {
    public init() {}

    public func run(textCount: Int = 100_000, imageMetaCount: Int = 1_000) -> BenchmarkReport {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PasteRushBench-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("bench.sqlite").path
        let db = Database(path: dbPath)
        let repo = ClipRepository(db: db)
        let search = SearchRepository(db: db)

        let samples = Self.sampleTexts()
        let t0 = CFAbsoluteTimeGetCurrent()
        for i in 0..<textCount {
            let text = samples[i % samples.count] + " #\(i)"
            let clip = ClipRecord(
                primaryType: .text,
                searchText: text,
                preview: String(text.prefix(120)),
                contentHash: ContentHasher.hashText(text + "-bench-\(i)"),
                totalBytes: text.utf8.count,
                sourceAppName: i % 3 == 0 ? "Safari" : (i % 3 == 1 ? "Cursor" : "Terminal"),
                formats: [ClipFormat(uti: "public.utf8-plain-text", inlineData: Data(text.utf8), textContent: text, byteSize: text.utf8.count)]
            )
            _ = repo.insert(clip, bumpExistingDuplicates: false, allowDuplicates: true)
        }
        for i in 0..<imageMetaCount {
            let clip = ClipRecord(
                primaryType: .image,
                searchText: "image screenshot \(i)",
                preview: "Image 800×600 #\(i)",
                contentHash: ContentHasher.hashText("image-bench-\(i)"),
                totalBytes: 120_000,
                sourceAppName: "Preview",
                imageWidth: 800,
                imageHeight: 600,
                formats: [ClipFormat(uti: "public.png", byteSize: 120_000)]
            )
            _ = repo.insert(clip, bumpExistingDuplicates: false, allowDuplicates: true)
        }
        let insertMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

        let t1 = CFAbsoluteTimeGetCurrent()
        _ = search.search(SearchQuery(raw: "json Cursor"))
        let searchMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000

        let t2 = CFAbsoluteTimeGetCurrent()
        _ = repo.recent(limit: 200)
        let recentMs = (CFAbsoluteTimeGetCurrent() - t2) * 1000

        let total = repo.stats().clipCount
        let summary = String(
            format: "Benchmark: %d clips | insert %.0fms | search %.1fms | recent200 %.1fms",
            total, insertMs, searchMs, recentMs
        )
        NSLog("%@", summary)

        // write report
        let reportURL = AppPaths.applicationSupport.appendingPathComponent("BenchmarkResults.txt")
        try? summary.write(to: reportURL, atomically: true, encoding: .utf8)

        return BenchmarkReport(insertTextMs: insertMs, searchMs: searchMs, recentMs: recentMs, totalClips: total, summary: summary)
    }

    public static func sampleTexts() -> [String] {
        [
            "Zażółć gęślą jaźń — polskie znaki w schowku",
            "https://example.com/path?query=1&lang=pl",
            "{\"name\":\"PasteRush\",\"version\":1,\"items\":[1,2,3]}",
            "func hello() {\n  print(\"Hello\")\n}",
            "SELECT * FROM clips WHERE search_text MATCH 'test*';",
            "/Users/fabian/Desktop/Projekty/ditto copy/file.swift",
            "C:\\Users\\Fabian\\Documents\\notes.txt",
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " + String(repeating: "word ", count: 80),
            "Krótki tekst",
            "email@example.com oraz numer +48 500 100 200"
        ]
    }
}

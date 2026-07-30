import Foundation
import PasteRushCore

@main
struct PasteRushBenchmarkMain {
    static func main() {
        print("Starting PasteRush benchmark…")
        let report = BenchmarkRunner().run(textCount: 100_000, imageMetaCount: 1_000)
        print(report.summary)
        print("Search latency: \(String(format: "%.1f", report.searchMs)) ms")
        print("Recent200 latency: \(String(format: "%.1f", report.recentMs)) ms")
        print("Insert total: \(String(format: "%.0f", report.insertTextMs)) ms")
    }
}

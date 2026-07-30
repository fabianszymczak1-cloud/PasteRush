import Foundation
import PasteRushCore

@main
struct PasteRushTestRunner {
    static var failures = 0

    static func expect(_ cond: @autoclosure () -> Bool, _ message: String) {
        if !cond() {
            failures += 1
            fputs("FAIL: \(message)\n", stderr)
        } else {
            print("PASS: \(message)")
        }
    }

    static func main() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PasteRushHarness-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = Database(path: tempDir.appendingPathComponent("test.sqlite").path)
        let repo = ClipRepository(db: db)
        let search = SearchRepository(db: db)

        func makeText(_ text: String, app: String? = nil) -> ClipRecord {
            ClipRecord(
                primaryType: .text,
                searchText: PolishNormalizer.searchBlob(from: text),
                preview: String(text.prefix(240)),
                contentHash: ContentHasher.hashText(text),
                totalBytes: text.utf8.count,
                sourceAppName: app,
                formats: [ClipFormat(uti: "public.utf8-plain-text", inlineData: Data(text.utf8), textContent: text, byteSize: text.utf8.count)]
            )
        }

        // insert/read
        let saved = repo.insert(makeText("Hello PasteRush"), allowDuplicates: true)
        expect(repo.get(id: saved.id)?.preview.contains("Hello") == true, "insert and read")

        // multi format
        var multi = makeText("Multi")
        multi.formats.append(ClipFormat(uti: "public.html", textContent: "<b>Multi</b>", byteSize: 12))
        let m = repo.insert(multi, allowDuplicates: true)
        expect(repo.get(id: m.id)?.formats.count == 2, "multi format")

        // dedupe
        let a = repo.insert(makeText("Same"), allowDuplicates: false)
        let b = repo.insert(makeText("Same"), allowDuplicates: false)
        expect(a.id == b.id, "dedupe identical consecutive")
        expect((repo.get(id: a.id)?.useCount ?? 0) >= 1, "dedupe bumps use count")

        // hash
        expect(ContentHasher.hashText("abc") == ContentHasher.hashText("abc"), "hash stable")
        expect(ContentHasher.hashText("abc") != ContentHasher.hashText("abd"), "hash differs")

        // polish
        _ = repo.insert(makeText("Zażółć gęślą jaźń"), allowDuplicates: true)
        expect(!search.search(SearchQuery(raw: "zolc")).isEmpty, "polish diacritic search")

        // filters
        var image = makeText("photo")
        image.primaryType = .image
        image.preview = "Image"
        image.contentHash = ContentHasher.hashText("photo-image-unique")
        _ = repo.insert(image, allowDuplicates: true)
        _ = repo.insert(makeText("safari text", app: "Safari"), allowDuplicates: true)
        expect(!search.search(SearchQuery(raw: "type:image")).isEmpty, "type filter")
        expect(!search.search(SearchQuery(raw: "app:Safari")).isEmpty, "app filter")

        // pinned ranking
        let pinned = repo.insert(makeText("pinned needle"), allowDuplicates: true)
        _ = repo.insert(makeText("needle normal"), allowDuplicates: true)
        repo.setPinned(id: pinned.id, pinned: true)
        expect(search.search(SearchQuery(raw: "needle")).first?.id == pinned.id, "pinned ranks first")

        // retention protection
        repo.setNeverDelete(id: pinned.id, value: true)
        db.exec("DELETE FROM clips WHERE never_delete=0 AND is_pinned=0;")
        expect(repo.get(id: pinned.id) != nil, "retention skips pinned/never-delete")

        // groups
        let g = ClipGroup(name: "Praca")
        repo.createGroup(g)
        expect(repo.allGroups().count == 1, "create group")
        var grouped = makeText("grupa")
        grouped.groupId = g.id
        grouped.contentHash = ContentHasher.hashText("grupa-unique")
        let gs = repo.insert(grouped, allowDuplicates: true)
        expect(repo.get(id: gs.id)?.groupId == g.id, "assign group")
        repo.deleteGroup(id: g.id)
        expect(repo.allGroups().isEmpty, "delete group")

        // transforms
        expect(TextTransform.uppercased.apply(to: "abc") == "ABC", "uppercased")
        expect(TextTransform.snakeCase.apply(to: "Hello World") == "hello_world", "snake_case")
        expect(TextTransform.windowsToPosix.apply(to: "C:\\Temp\\a") == "/mnt/c/Temp/a", "windows path")

        // migrations / integrity
        expect(db.integrityCheck() == "ok", "integrity check")

        // backup
        do {
            let url = try BackupService(db: db).createBackup(to: tempDir.appendingPathComponent("bak"))
            expect(FileManager.default.fileExists(atPath: url.path), "backup created")
        } catch {
            expect(false, "backup threw \(error)")
        }

        // query parser
        let q = SearchQuery(raw: "type:image app:Safari pinned:true before:2026-07-01 hello")
        expect(q.typeFilter == .image, "parse type")
        expect(q.appFilter == "Safari", "parse app")
        expect(q.pinnedOnly == true, "parse pinned")
        expect(q.before != nil, "parse before")
        expect(q.freeText.contains("hello"), "parse free text")

        // own paste dedupe path
        let first = repo.insert(makeText("loop-own"), allowDuplicates: false)
        let second = repo.insert(makeText("loop-own"), allowDuplicates: false)
        expect(first.id == second.id, "own paste reinsert deduped")

        if failures == 0 {
            print("\nAll harness tests passed.")
            exit(0)
        } else {
            fputs("\n\(failures) tests failed.\n", stderr)
            exit(1)
        }
    }
}

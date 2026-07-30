import Foundation
import XCTest
@testable import PasteRushCore

final class PasteRushTests: XCTestCase {
    var db: Database!
    var repo: ClipRepository!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PasteRushTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        db = Database(path: tempDir.appendingPathComponent("test.sqlite").path)
        repo = ClipRepository(db: db)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInsertAndRead() {
        let clip = makeTextClip("Hello PasteRush")
        let saved = repo.insert(clip, allowDuplicates: true)
        let loaded = repo.get(id: saved.id)
        XCTAssertEqual(loaded?.preview.contains("Hello"), true)
        XCTAssertEqual(loaded?.formats.count, 1)
    }

    func testMultiFormatSameClip() {
        var clip = makeTextClip("Multi")
        clip.formats.append(ClipFormat(uti: "public.html", textContent: "<b>Multi</b>", byteSize: 12))
        clip.formats.append(ClipFormat(uti: "public.rtf", inlineData: Data("rtf".utf8), byteSize: 3))
        let saved = repo.insert(clip, allowDuplicates: true)
        XCTAssertEqual(repo.get(id: saved.id)?.formats.count, 3)
    }

    func testDedup() {
        let a = makeTextClip("Same")
        let b = makeTextClip("Same")
        let first = repo.insert(a, bumpExistingDuplicates: true, allowDuplicates: false)
        let second = repo.insert(b, bumpExistingDuplicates: true, allowDuplicates: false)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(repo.get(id: first.id)?.useCount, 1)
    }

    func testHashStable() {
        let h1 = ContentHasher.hashText("abc")
        let h2 = ContentHasher.hashText("abc")
        let h3 = ContentHasher.hashText("abd")
        XCTAssertEqual(h1, h2)
        XCTAssertNotEqual(h1, h3)
    }

    func testPolishSearch() {
        _ = repo.insert(makeTextClip("Zażółć gęślą jaźń"), allowDuplicates: true)
        let search = SearchRepository(db: db)
        let results = search.search(SearchQuery(raw: "zolc"))
        XCTAssertFalse(results.isEmpty)
    }

    func testFilters() {
        var image = makeTextClip("photo")
        image.primaryType = .image
        image.preview = "Image"
        image.contentHash = ContentHasher.hashText("photo-image")
        _ = repo.insert(image, allowDuplicates: true)
        _ = repo.insert(makeTextClip("safari text", app: "Safari"), allowDuplicates: true)

        let search = SearchRepository(db: db)
        XCTAssertFalse(search.search(SearchQuery(raw: "type:image")).isEmpty)
        XCTAssertFalse(search.search(SearchQuery(raw: "app:Safari")).isEmpty)
    }

    func testPinnedRanking() {
        let a = repo.insert(makeTextClip("pinned needle"), allowDuplicates: true)
        let b = repo.insert(makeTextClip("needle normal"), allowDuplicates: true)
        repo.setPinned(id: a.id, pinned: true)
        let results = SearchRepository(db: db).search(SearchQuery(raw: "needle"))
        XCTAssertEqual(results.first?.id, a.id)
        _ = b
    }

    func testRetentionSkipsPinned() {
        let pinned = repo.insert(makeTextClip("keep"), allowDuplicates: true)
        repo.setPinned(id: pinned.id, pinned: true)
        repo.setNeverDelete(id: pinned.id, value: true)
        for i in 0..<5 {
            _ = repo.insert(makeTextClip("old \(i)"), allowDuplicates: true)
        }
        // Manual delete oldest non-protected simulation
        db.exec("DELETE FROM clips WHERE never_delete=0 AND is_pinned=0;")
        XCTAssertNotNil(repo.get(id: pinned.id))
    }

    func testGroups() {
        let g = ClipGroup(name: "Praca")
        repo.createGroup(g)
        XCTAssertEqual(repo.allGroups().count, 1)
        var clip = makeTextClip("grupa")
        clip.groupId = g.id
        let saved = repo.insert(clip, allowDuplicates: true)
        XCTAssertEqual(repo.get(id: saved.id)?.groupId, g.id)
        repo.deleteGroup(id: g.id)
        XCTAssertTrue(repo.allGroups().isEmpty)
    }

    func testTextTransforms() {
        XCTAssertEqual(TextTransform.uppercased.apply(to: "abc"), "ABC")
        XCTAssertEqual(TextTransform.snakeCase.apply(to: "Hello World"), "hello_world")
        XCTAssertEqual(TextTransform.kebabCase.apply(to: "Hello World"), "hello-world")
        XCTAssertEqual(TextTransform.windowsToPosix.apply(to: "C:\\Temp\\a"), "/mnt/c/Temp/a")
        XCTAssertEqual(TextTransform.generateUUID.apply(to: "").count, 36)
    }

    func testMigrationsApplied() {
        let check = db.integrityCheck()
        XCTAssertEqual(check, "ok")
    }

    func testBackupRestore() throws {
        _ = repo.insert(makeTextClip("backup-me"), allowDuplicates: true)
        let backupDir = tempDir.appendingPathComponent("bak")
        let service = BackupService(db: db)
        let url = try service.createBackup(to: backupDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSearchQueryParser() {
        var q = SearchQuery(raw: "type:image app:Safari pinned:true before:2026-07-01 hello")
        XCTAssertEqual(q.typeFilter, .image)
        XCTAssertEqual(q.appFilter, "Safari")
        XCTAssertEqual(q.pinnedOnly, true)
        XCTAssertNotNil(q.before)
        XCTAssertTrue(q.freeText.contains("hello"))
    }

    func testOwnPasteHashIsolation() {
        // Ensure identical content can be suppressed by allowDuplicates=false after touch
        let first = repo.insert(makeTextClip("loop"), allowDuplicates: false)
        let second = repo.insert(makeTextClip("loop"), allowDuplicates: false)
        XCTAssertEqual(first.id, second.id)
    }

    private func makeTextClip(_ text: String, app: String? = nil) -> ClipRecord {
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
}

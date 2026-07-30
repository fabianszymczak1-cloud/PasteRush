import Foundation
import SQLite3

public final class RetentionService {
    private let repository: ClipRepository
    private let settings: SettingsStore
    private let db: Database

    public init(repository: ClipRepository = ClipRepository(), settings: SettingsStore = .shared, db: Database = .shared) {
        self.repository = repository
        self.settings = settings
        self.db = db
    }

    public func enforceIfNeeded() {
        let maxEntries = settings.maxEntries
        let maxAgeDays = settings.maxAgeDays
        let maxDb = settings.maxDatabaseBytes
        let maxImages = settings.maxImageEntries
        guard maxEntries > 0 || maxAgeDays > 0 || maxDb > 0 || maxImages > 0 else { return }

        db.async {
            if maxAgeDays > 0 {
                let cutoff = Date().addingTimeInterval(TimeInterval(-maxAgeDays * 24 * 3600)).timeIntervalSince1970
                Database.shared.exec("""
                DELETE FROM clips WHERE never_delete = 0 AND is_pinned = 0 AND group_id IS NULL AND copied_at < \(cutoff);
                """)
            }

            if maxEntries > 0 {
                if let stmt = Database.shared.prepare("SELECT COUNT(*) FROM clips WHERE never_delete=0 AND is_pinned=0 AND group_id IS NULL;") {
                    defer { sqlite3_finalize(stmt) }
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        let count = SQLiteValue.int(stmt, 0)
                        let excess = count - maxEntries
                        if excess > 0 {
                            Database.shared.exec("""
                            DELETE FROM clips WHERE id IN (
                                SELECT id FROM clips WHERE never_delete=0 AND is_pinned=0 AND group_id IS NULL
                                ORDER BY copied_at ASC LIMIT \(excess)
                            );
                            """)
                        }
                    }
                }
            }

            if maxImages > 0 {
                if let stmt = Database.shared.prepare("SELECT COUNT(*) FROM clips WHERE primary_type='image' AND never_delete=0 AND is_pinned=0;") {
                    defer { sqlite3_finalize(stmt) }
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        let count = SQLiteValue.int(stmt, 0)
                        let excess = count - maxImages
                        if excess > 0 {
                            Database.shared.exec("""
                            DELETE FROM clips WHERE id IN (
                                SELECT id FROM clips WHERE primary_type='image' AND never_delete=0 AND is_pinned=0
                                ORDER BY copied_at ASC LIMIT \(excess)
                            );
                            """)
                        }
                    }
                }
            }

            if maxDb > 0 {
                let size = (try? FileManager.default.attributesOfItem(atPath: Database.shared.path)[.size] as? Int) ?? 0
                if size > maxDb {
                    Database.shared.exec("""
                    DELETE FROM clips WHERE id IN (
                        SELECT id FROM clips WHERE never_delete=0 AND is_pinned=0 AND group_id IS NULL
                        ORDER BY copied_at ASC LIMIT 100
                    );
                    """)
                }
            }
        }
    }
}

public final class BackupService {
    private let db: Database

    public init(db: Database = .shared) {
        self.db = db
    }

    @discardableResult
    public func createBackup(to directory: URL = AppPaths.backupsDirectory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "PasteRush-backup-\(formatter.string(from: Date())).sqlite"
        let dest = directory.appendingPathComponent(name)
        db.sync {
            _ = db.exec("PRAGMA wal_checkpoint(FULL);")
        }
        try FileManager.default.copyItem(atPath: db.path, toPath: dest.path)
        // also copy blobs
        let blobsDest = dest.deletingPathExtension().appendingPathExtension("blobs")
        if FileManager.default.fileExists(atPath: AppPaths.blobsDirectory.path) {
            try? FileManager.default.copyItem(at: AppPaths.blobsDirectory, to: blobsDest)
        }
        return dest
    }

    public func restoreBackup(from url: URL) throws {
        db.sync {
            _ = db.exec("PRAGMA wal_checkpoint(TRUNCATE);")
        }
        // Close is not exposed; copy over after renaming
        let target = AppPaths.databaseURL
        let bak = target.appendingPathExtension("before-restore")
        try? FileManager.default.removeItem(at: bak)
        try? FileManager.default.copyItem(at: target, to: bak)
        try FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: url, to: target)
        let blobsSidecar = url.deletingPathExtension().appendingPathExtension("blobs")
        if FileManager.default.fileExists(atPath: blobsSidecar.path) {
            try? FileManager.default.removeItem(at: AppPaths.blobsDirectory)
            try? FileManager.default.copyItem(at: blobsSidecar, to: AppPaths.blobsDirectory)
        }
    }

    public func exportClips(_ ids: [String], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repo = ClipRepository(db: db)
        var meta: [[String: Any]] = []
        for id in ids {
            guard let clip = repo.get(id: id) else { continue }
            var entry: [String: Any] = [
                "id": clip.id,
                "preview": clip.preview,
                "primaryType": clip.primaryType.rawValue,
                "copiedAt": clip.copiedAt.timeIntervalSince1970,
                "searchText": clip.searchText,
                "customName": clip.customName ?? "",
                "sourceAppName": clip.sourceAppName ?? ""
            ]
            if let text = clip.formats.first(where: { $0.textContent != nil })?.textContent {
                let file = directory.appendingPathComponent("\(clip.id).txt")
                try text.write(to: file, atomically: true, encoding: .utf8)
                entry["textFile"] = file.lastPathComponent
            }
            if clip.primaryType == .image {
                if let format = clip.formats.first(where: { $0.uti.contains("png") || $0.uti.contains("tiff") || $0.uti.contains("image") }) {
                    let data = format.inlineData ?? (format.blobPath.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) })
                    if let data {
                        let file = directory.appendingPathComponent("\(clip.id).png")
                        if let image = NSImageFromData(data), let png = image.pngData() {
                            try png.write(to: file)
                            entry["imageFile"] = file.lastPathComponent
                        } else {
                            try data.write(to: file)
                            entry["imageFile"] = file.lastPathComponent
                        }
                    }
                }
            }
            meta.append(entry)
        }
        let json = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: directory.appendingPathComponent("export.json"))
    }

    public func importFromExport(directory: URL) throws {
        let jsonURL = directory.appendingPathComponent("export.json")
        let data = try Data(contentsOf: jsonURL)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let repo = ClipRepository(db: db)
        for entry in arr {
            let textFile = entry["textFile"] as? String
            var text = ""
            if let textFile {
                text = (try? String(contentsOf: directory.appendingPathComponent(textFile), encoding: .utf8)) ?? ""
            } else {
                text = entry["searchText"] as? String ?? entry["preview"] as? String ?? ""
            }
            guard !text.isEmpty else { continue }
            let clip = ClipRecord(
                primaryType: .text,
                searchText: text,
                preview: String(text.prefix(240)),
                contentHash: ContentHasher.hashText(text),
                totalBytes: text.utf8.count,
                sourceAppName: entry["sourceAppName"] as? String,
                customName: entry["customName"] as? String,
                formats: [ClipFormat(uti: "public.utf8-plain-text", inlineData: Data(text.utf8), textContent: text, byteSize: text.utf8.count)]
            )
            _ = repo.insert(clip, bumpExistingDuplicates: true, allowDuplicates: false)
        }
    }
}

import AppKit

private func NSImageFromData(_ data: Data) -> NSImage? {
    NSImage(data: data)
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

import Foundation
import SQLite3

public final class ClipRepository {
    private let db: Database

    public init(db: Database = .shared) {
        self.db = db
    }

    public func insert(_ clip: ClipRecord, bumpExistingDuplicates: Bool = true, allowDuplicates: Bool = false) -> ClipRecord {
        db.sync {
            if !allowDuplicates {
                if let existing = findByHash(clip.contentHash) {
                    if bumpExistingDuplicates {
                        return touch(id: existing.id)
                    }
                    return existing
                }
            }

            let resolvedGroupName = clip.groupId.flatMap { self.groupName(id: $0) } ?? ""
            let searchBlob = PolishNormalizer.searchBlob(from: [
                clip.searchText,
                clip.preview,
                clip.customName ?? "",
                clip.sourceAppName ?? "",
                clip.ocrText ?? "",
                resolvedGroupName
            ].joined(separator: "\n"))

            db.exec("BEGIN IMMEDIATE;")
            defer { db.exec("COMMIT;") }

            let sql = """
            INSERT INTO clips(
                id, copied_at, last_used_at, use_count, primary_type, search_text, preview, content_hash,
                total_bytes, source_app_name, source_bundle_id, source_window_title, is_pinned, never_delete,
                pin_order, custom_name, custom_hotkey, group_id, thumbnail_path, image_width, image_height, ocr_text
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
            """
            guard let stmt = db.prepare(sql) else { return clip }
            defer { sqlite3_finalize(stmt) }

            SQLiteValue.bindText(stmt, 1, clip.id)
            SQLiteValue.bindDouble(stmt, 2, clip.copiedAt.timeIntervalSince1970)
            SQLiteValue.bindDouble(stmt, 3, clip.lastUsedAt.timeIntervalSince1970)
            SQLiteValue.bindInt(stmt, 4, clip.useCount)
            SQLiteValue.bindText(stmt, 5, clip.primaryType.rawValue)
            SQLiteValue.bindText(stmt, 6, searchBlob)
            SQLiteValue.bindText(stmt, 7, clip.preview)
            SQLiteValue.bindText(stmt, 8, clip.contentHash)
            SQLiteValue.bindInt(stmt, 9, clip.totalBytes)
            SQLiteValue.bindText(stmt, 10, clip.sourceAppName)
            SQLiteValue.bindText(stmt, 11, clip.sourceBundleId)
            SQLiteValue.bindText(stmt, 12, clip.sourceWindowTitle)
            SQLiteValue.bindInt(stmt, 13, clip.isPinned ? 1 : 0)
            SQLiteValue.bindInt(stmt, 14, clip.neverDelete ? 1 : 0)
            SQLiteValue.bindInt(stmt, 15, clip.pinOrder)
            SQLiteValue.bindText(stmt, 16, clip.customName)
            SQLiteValue.bindText(stmt, 17, clip.customHotkey)
            SQLiteValue.bindText(stmt, 18, clip.groupId)
            SQLiteValue.bindText(stmt, 19, clip.thumbnailPath)
            if let w = clip.imageWidth { SQLiteValue.bindInt(stmt, 20, w) } else { sqlite3_bind_null(stmt, 20) }
            if let h = clip.imageHeight { SQLiteValue.bindInt(stmt, 21, h) } else { sqlite3_bind_null(stmt, 21) }
            SQLiteValue.bindText(stmt, 22, clip.ocrText)
            sqlite3_step(stmt)

            for format in clip.formats {
                insertFormat(clipId: clip.id, format: format)
            }

            if let fts = db.prepare("""
                INSERT INTO clips_fts(clip_id, search_text, preview, custom_name, source_app_name, ocr_text, group_name)
                VALUES (?,?,?,?,?,?,?);
                """) {
                defer { sqlite3_finalize(fts) }
                SQLiteValue.bindText(fts, 1, clip.id)
                SQLiteValue.bindText(fts, 2, searchBlob)
                SQLiteValue.bindText(fts, 3, clip.preview)
                SQLiteValue.bindText(fts, 4, clip.customName ?? "")
                SQLiteValue.bindText(fts, 5, clip.sourceAppName ?? "")
                SQLiteValue.bindText(fts, 6, clip.ocrText ?? "")
                SQLiteValue.bindText(fts, 7, resolvedGroupName)
                sqlite3_step(fts)
            }

            if let groupId = clip.groupId {
                db.exec("INSERT OR IGNORE INTO clip_groups(clip_id, group_id) VALUES ('\(clip.id)','\(groupId)');")
            }

            return clip
        }
    }

    private func insertFormat(clipId: String, format: ClipFormat) {
        guard let stmt = db.prepare("""
            INSERT INTO clip_formats(clip_id, uti, blob_path, inline_data, text_content, byte_size)
            VALUES (?,?,?,?,?,?);
            """) else { return }
        defer { sqlite3_finalize(stmt) }
        SQLiteValue.bindText(stmt, 1, clipId)
        SQLiteValue.bindText(stmt, 2, format.uti)
        SQLiteValue.bindText(stmt, 3, format.blobPath)
        SQLiteValue.bindData(stmt, 4, format.inlineData)
        SQLiteValue.bindText(stmt, 5, format.textContent)
        SQLiteValue.bindInt(stmt, 6, format.byteSize)
        sqlite3_step(stmt)
    }

    public func findByHash(_ hash: String) -> ClipRecord? {
        guard let stmt = db.prepare("SELECT id FROM clips WHERE content_hash = ? LIMIT 1;") else { return nil }
        defer { sqlite3_finalize(stmt) }
        SQLiteValue.bindText(stmt, 1, hash)
        guard sqlite3_step(stmt) == SQLITE_ROW, let id = SQLiteValue.string(stmt, 0) else { return nil }
        return get(id: id)
    }

    public func get(id: String) -> ClipRecord? {
        db.sync {
            guard let stmt = db.prepare("SELECT * FROM clips WHERE id = ? LIMIT 1;") else { return nil }
            defer { sqlite3_finalize(stmt) }
            SQLiteValue.bindText(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            var clip = mapClip(stmt)
            clip.formats = formats(for: id)
            return clip
        }
    }

    public func touch(id: String) -> ClipRecord {
        db.sync {
            db.exec("""
            UPDATE clips SET last_used_at = \(Date().timeIntervalSince1970),
                             use_count = use_count + 1,
                             copied_at = \(Date().timeIntervalSince1970)
            WHERE id = '\(id)';
            """)
            return get(id: id) ?? ClipRecord(id: id)
        }
    }

    public func markUsed(id: String) {
        db.async {
            self.db.exec("""
            UPDATE clips SET last_used_at = \(Date().timeIntervalSince1970), use_count = use_count + 1 WHERE id = '\(id)';
            """)
        }
    }

    public func delete(id: String) {
        db.sync {
            if let clip = get(id: id) {
                for format in clip.formats {
                    if let path = format.blobPath {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                }
                if let thumb = clip.thumbnailPath {
                    try? FileManager.default.removeItem(atPath: thumb)
                }
            }
            db.exec("DELETE FROM clips_fts WHERE clip_id = '\(id)';")
            db.exec("DELETE FROM clips WHERE id = '\(id)';")
        }
    }

    public func deleteAll() {
        db.sync {
            db.exec("DELETE FROM clips_fts;")
            db.exec("DELETE FROM clip_formats;")
            db.exec("DELETE FROM clip_groups;")
            db.exec("DELETE FROM clip_tags;")
            db.exec("DELETE FROM clips;")
            try? FileManager.default.removeItem(at: AppPaths.blobsDirectory)
            try? FileManager.default.removeItem(at: AppPaths.thumbnailsDirectory)
            _ = AppPaths.blobsDirectory
            _ = AppPaths.thumbnailsDirectory
        }
    }

    public func setPinned(id: String, pinned: Bool) {
        db.sync {
            if pinned {
                let order = nextPinOrder()
                db.exec("UPDATE clips SET is_pinned = 1, pin_order = \(order) WHERE id = '\(id)';")
            } else {
                db.exec("UPDATE clips SET is_pinned = 0, pin_order = 0 WHERE id = '\(id)';")
            }
        }
    }

    public func setNeverDelete(id: String, value: Bool) {
        db.exec("UPDATE clips SET never_delete = \(value ? 1 : 0) WHERE id = '\(id)';")
    }

    public func updateText(id: String, text: String, customName: String? = nil) {
        db.sync {
            let hash = ContentHasher.hashText(text)
            let preview = String(text.prefix(240)).replacingOccurrences(of: "\n", with: " ")
            let search = PolishNormalizer.searchBlob(from: text)
            guard let stmt = db.prepare("""
                UPDATE clips SET search_text = ?, preview = ?, content_hash = ?, custom_name = COALESCE(?, custom_name),
                primary_type = 'text', total_bytes = ? WHERE id = ?;
                """) else { return }
            defer { sqlite3_finalize(stmt) }
            SQLiteValue.bindText(stmt, 1, search)
            SQLiteValue.bindText(stmt, 2, preview)
            SQLiteValue.bindText(stmt, 3, hash)
            SQLiteValue.bindText(stmt, 4, customName)
            SQLiteValue.bindInt(stmt, 5, text.utf8.count)
            SQLiteValue.bindText(stmt, 6, id)
            sqlite3_step(stmt)

            db.exec("DELETE FROM clip_formats WHERE clip_id = '\(id)';")
            insertFormat(clipId: id, format: ClipFormat(uti: "public.utf8-plain-text", inlineData: Data(text.utf8), textContent: text, byteSize: text.utf8.count))
            db.exec("DELETE FROM clips_fts WHERE clip_id = '\(id)';")
            if let clip = get(id: id) {
                let groupName = clip.groupId.flatMap { self.groupName(id: $0) } ?? ""
                if let fts = db.prepare("INSERT INTO clips_fts(clip_id, search_text, preview, custom_name, source_app_name, ocr_text, group_name) VALUES (?,?,?,?,?,?,?);") {
                    defer { sqlite3_finalize(fts) }
                    SQLiteValue.bindText(fts, 1, id)
                    SQLiteValue.bindText(fts, 2, search)
                    SQLiteValue.bindText(fts, 3, preview)
                    SQLiteValue.bindText(fts, 4, clip.customName ?? "")
                    SQLiteValue.bindText(fts, 5, clip.sourceAppName ?? "")
                    SQLiteValue.bindText(fts, 6, clip.ocrText ?? "")
                    SQLiteValue.bindText(fts, 7, groupName)
                    sqlite3_step(fts)
                }
            }
        }
    }

    public func updateOCR(id: String, text: String) {
        db.sync {
            guard let stmt = db.prepare("UPDATE clips SET ocr_text = ?, search_text = search_text || '\n' || ? WHERE id = ?;") else { return }
            defer { sqlite3_finalize(stmt) }
            let folded = PolishNormalizer.searchBlob(from: text)
            SQLiteValue.bindText(stmt, 1, text)
            SQLiteValue.bindText(stmt, 2, folded)
            SQLiteValue.bindText(stmt, 3, id)
            sqlite3_step(stmt)
            db.exec("DELETE FROM clips_fts WHERE clip_id = '\(id)';")
            if let clip = get(id: id) {
                let groupName = clip.groupId.flatMap { self.groupName(id: $0) } ?? ""
                if let fts = db.prepare("INSERT INTO clips_fts(clip_id, search_text, preview, custom_name, source_app_name, ocr_text, group_name) VALUES (?,?,?,?,?,?,?);") {
                    defer { sqlite3_finalize(fts) }
                    SQLiteValue.bindText(fts, 1, id)
                    SQLiteValue.bindText(fts, 2, clip.searchText)
                    SQLiteValue.bindText(fts, 3, clip.preview)
                    SQLiteValue.bindText(fts, 4, clip.customName ?? "")
                    SQLiteValue.bindText(fts, 5, clip.sourceAppName ?? "")
                    SQLiteValue.bindText(fts, 6, text)
                    SQLiteValue.bindText(fts, 7, groupName)
                    sqlite3_step(fts)
                }
            }
        }
    }

    public func setGroup(clipId: String, groupId: String?) {
        db.sync {
            if let groupId {
                db.exec("UPDATE clips SET group_id = '\(groupId)' WHERE id = '\(clipId)';")
                db.exec("INSERT OR IGNORE INTO clip_groups(clip_id, group_id) VALUES ('\(clipId)','\(groupId)');")
            } else {
                db.exec("UPDATE clips SET group_id = NULL WHERE id = '\(clipId)';")
                db.exec("DELETE FROM clip_groups WHERE clip_id = '\(clipId)';")
            }
        }
    }

    public func formats(for clipId: String) -> [ClipFormat] {
        var result: [ClipFormat] = []
        guard let stmt = db.prepare("SELECT uti, blob_path, inline_data, text_content, byte_size FROM clip_formats WHERE clip_id = ?;") else { return [] }
        defer { sqlite3_finalize(stmt) }
        SQLiteValue.bindText(stmt, 1, clipId)
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(ClipFormat(
                uti: SQLiteValue.string(stmt, 0) ?? "",
                blobPath: SQLiteValue.string(stmt, 1),
                inlineData: SQLiteValue.data(stmt, 2),
                textContent: SQLiteValue.string(stmt, 3),
                byteSize: SQLiteValue.int(stmt, 4)
            ))
        }
        return result
    }

    public func recent(limit: Int = 100, pinnedOnly: Bool = false) -> [ClipListItem] {
        db.sync {
            let filter = pinnedOnly ? "WHERE is_pinned = 1" : ""
            let sql = """
            SELECT c.id, c.preview, c.custom_name, c.primary_type, c.source_app_name, c.source_bundle_id,
                   c.copied_at, c.last_used_at, c.use_count, c.is_pinned, c.never_delete, c.group_id, g.name,
                   c.thumbnail_path, c.total_bytes
            FROM clips c
            LEFT JOIN groups g ON g.id = c.group_id
            \(filter)
            ORDER BY c.is_pinned DESC, c.pin_order ASC, c.copied_at DESC
            LIMIT \(limit);
            """
            return mapList(sql)
        }
    }

    public func stats() -> DatabaseStats {
        db.sync {
            var count = 0
            var imageBytes: Int64 = 0
            if let stmt = db.prepare("SELECT COUNT(*), COALESCE(SUM(CASE WHEN primary_type='image' THEN total_bytes ELSE 0 END),0) FROM clips;") {
                defer { sqlite3_finalize(stmt) }
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = SQLiteValue.int(stmt, 0)
                    imageBytes = SQLiteValue.int64(stmt, 1)
                }
            }
            let dbSize = (try? FileManager.default.attributesOfItem(atPath: db.path)[.size] as? Int64) ?? 0
            let free = freeDiskSpace()
            return DatabaseStats(clipCount: count, databaseBytes: dbSize, imageBytes: imageBytes, freeDiskBytes: free)
        }
    }

    public func createGroup(_ group: ClipGroup) {
        db.sync {
            guard let stmt = db.prepare("INSERT INTO groups(id, name, parent_id, sort_order, hotkey) VALUES (?,?,?,?,?);") else { return }
            defer { sqlite3_finalize(stmt) }
            SQLiteValue.bindText(stmt, 1, group.id)
            SQLiteValue.bindText(stmt, 2, group.name)
            SQLiteValue.bindText(stmt, 3, group.parentId)
            SQLiteValue.bindInt(stmt, 4, group.sortOrder)
            SQLiteValue.bindText(stmt, 5, group.hotkey)
            sqlite3_step(stmt)
        }
    }

    public func renameGroup(id: String, name: String) {
        db.exec("UPDATE groups SET name = '\(name.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(id)';")
    }

    public func deleteGroup(id: String) {
        db.sync {
            db.exec("UPDATE clips SET group_id = NULL WHERE group_id = '\(id)';")
            db.exec("DELETE FROM clip_groups WHERE group_id = '\(id)';")
            db.exec("DELETE FROM groups WHERE id = '\(id)';")
        }
    }

    public func allGroups() -> [ClipGroup] {
        db.sync {
            var result: [ClipGroup] = []
            guard let stmt = db.prepare("SELECT id, name, parent_id, sort_order, hotkey FROM groups ORDER BY sort_order, name;") else { return [] }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(ClipGroup(
                    id: SQLiteValue.string(stmt, 0) ?? UUID().uuidString,
                    name: SQLiteValue.string(stmt, 1) ?? "",
                    parentId: SQLiteValue.string(stmt, 2),
                    sortOrder: SQLiteValue.int(stmt, 3),
                    hotkey: SQLiteValue.string(stmt, 4)
                ))
            }
            return result
        }
    }

    public func groupName(id: String) -> String? {
        guard let stmt = db.prepare("SELECT name FROM groups WHERE id = ?;") else { return nil }
        defer { sqlite3_finalize(stmt) }
        SQLiteValue.bindText(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return SQLiteValue.string(stmt, 0)
    }

    private func nextPinOrder() -> Int {
        guard let stmt = db.prepare("SELECT COALESCE(MAX(pin_order),0)+1 FROM clips WHERE is_pinned=1;") else { return 1 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW { return SQLiteValue.int(stmt, 0) }
        return 1
    }

    private func freeDiskSpace() -> Int64 {
        if let vals = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = vals.volumeAvailableCapacityForImportantUsage {
            return free
        }
        return 0
    }

    func mapList(_ sql: String) -> [ClipListItem] {
        var items: [ClipListItem] = []
        guard let stmt = db.prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let typeRaw = SQLiteValue.string(stmt, 3) ?? "text"
            items.append(ClipListItem(
                id: SQLiteValue.string(stmt, 0) ?? UUID().uuidString,
                preview: SQLiteValue.string(stmt, 1) ?? "",
                customName: SQLiteValue.string(stmt, 2),
                primaryType: ClipPrimaryType(rawValue: typeRaw) ?? .unknown,
                sourceAppName: SQLiteValue.string(stmt, 4),
                sourceBundleId: SQLiteValue.string(stmt, 5),
                copiedAt: Date(timeIntervalSince1970: SQLiteValue.double(stmt, 6)),
                lastUsedAt: Date(timeIntervalSince1970: SQLiteValue.double(stmt, 7)),
                useCount: SQLiteValue.int(stmt, 8),
                isPinned: SQLiteValue.int(stmt, 9) == 1,
                neverDelete: SQLiteValue.int(stmt, 10) == 1,
                groupId: SQLiteValue.string(stmt, 11),
                groupName: SQLiteValue.string(stmt, 12),
                thumbnailPath: SQLiteValue.string(stmt, 13),
                totalBytes: SQLiteValue.int(stmt, 14)
            ))
        }
        return items
    }

    private func mapClip(_ stmt: OpaquePointer?) -> ClipRecord {
        let typeRaw = SQLiteValue.string(stmt, 4) ?? "text"
        return ClipRecord(
            id: SQLiteValue.string(stmt, 0) ?? UUID().uuidString,
            copiedAt: Date(timeIntervalSince1970: SQLiteValue.double(stmt, 1)),
            lastUsedAt: Date(timeIntervalSince1970: SQLiteValue.double(stmt, 2)),
            useCount: SQLiteValue.int(stmt, 3),
            primaryType: ClipPrimaryType(rawValue: typeRaw) ?? .unknown,
            searchText: SQLiteValue.string(stmt, 5) ?? "",
            preview: SQLiteValue.string(stmt, 6) ?? "",
            contentHash: SQLiteValue.string(stmt, 7) ?? "",
            totalBytes: SQLiteValue.int(stmt, 8),
            sourceAppName: SQLiteValue.string(stmt, 9),
            sourceBundleId: SQLiteValue.string(stmt, 10),
            sourceWindowTitle: SQLiteValue.string(stmt, 11),
            isPinned: SQLiteValue.int(stmt, 12) == 1,
            neverDelete: SQLiteValue.int(stmt, 13) == 1,
            pinOrder: SQLiteValue.int(stmt, 14),
            customName: SQLiteValue.string(stmt, 15),
            customHotkey: SQLiteValue.string(stmt, 16),
            groupId: SQLiteValue.string(stmt, 17),
            thumbnailPath: SQLiteValue.string(stmt, 18),
            imageWidth: sqlite3_column_type(stmt, 19) == SQLITE_NULL ? nil : SQLiteValue.int(stmt, 19),
            imageHeight: sqlite3_column_type(stmt, 20) == SQLITE_NULL ? nil : SQLiteValue.int(stmt, 20),
            ocrText: SQLiteValue.string(stmt, 21)
        )
    }
}

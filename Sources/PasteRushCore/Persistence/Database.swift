import Foundation
import SQLite3

public final class Database {
    public static let shared = Database(path: AppPaths.databaseURL.path)

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let asyncQueue = DispatchQueue(label: "com.pasterush.database.async", qos: .userInitiated)
    public let path: String

    public init(path: String) {
        self.path = path
        open()
        migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func open() {
        if sqlite3_open(path, &db) != SQLITE_OK {
            fatalError("Unable to open database at \(path)")
        }
        exec("PRAGMA foreign_keys = ON;")
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA synchronous = NORMAL;")
        exec("PRAGMA temp_store = MEMORY;")
        exec("PRAGMA mmap_size = 268435456;")
        exec("PRAGMA cache_size = -20000;")
    }

    public func sync<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    public func async(_ work: @escaping () -> Void) {
        asyncQueue.async { [weak self] in
            self?.sync(work)
        }
    }

    @discardableResult
    public func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &err)
        if result != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            NSLog("PasteRush SQL error: \(message) — \(sql.prefix(200))")
            return false
        }
        return true
    }

    public func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            NSLog("PasteRush prepare error: \(lastError()) — \(sql.prefix(200))")
            return nil
        }
        return stmt
    }

    public func lastError() -> String {
        String(cString: sqlite3_errmsg(db))
    }

    public func lastInsertRowId() -> Int64 {
        sqlite3_last_insert_rowid(db)
    }

    public func changes() -> Int32 {
        sqlite3_changes(db)
    }

    public var pointer: OpaquePointer? { db }

    public func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at REAL NOT NULL
        );
        """)

        let current = currentVersion()
        let migrations: [(Int, String)] = [
            (1, migrationV1),
            (2, migrationV2)
        ]

        for (version, sql) in migrations where version > current {
            exec("BEGIN IMMEDIATE;")
            let ok = exec(sql)
            if ok {
                exec("INSERT INTO schema_migrations(version, applied_at) VALUES (\(version), \(Date().timeIntervalSince1970));")
                exec("COMMIT;")
            } else {
                exec("ROLLBACK;")
                fatalError("Migration \(version) failed: \(lastError())")
            }
        }
    }

    private func currentVersion() -> Int {
        guard let stmt = prepare("SELECT COALESCE(MAX(version), 0) FROM schema_migrations;") else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    private var migrationV1: String {
        """
        CREATE TABLE clips (
            id TEXT PRIMARY KEY,
            copied_at REAL NOT NULL,
            last_used_at REAL NOT NULL,
            use_count INTEGER NOT NULL DEFAULT 0,
            primary_type TEXT NOT NULL,
            search_text TEXT NOT NULL DEFAULT '',
            preview TEXT NOT NULL DEFAULT '',
            content_hash TEXT NOT NULL,
            total_bytes INTEGER NOT NULL DEFAULT 0,
            source_app_name TEXT,
            source_bundle_id TEXT,
            source_window_title TEXT,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            never_delete INTEGER NOT NULL DEFAULT 0,
            pin_order INTEGER NOT NULL DEFAULT 0,
            custom_name TEXT,
            custom_hotkey TEXT,
            group_id TEXT,
            thumbnail_path TEXT,
            image_width INTEGER,
            image_height INTEGER,
            ocr_text TEXT
        );

        CREATE TABLE clip_formats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            clip_id TEXT NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
            uti TEXT NOT NULL,
            blob_path TEXT,
            inline_data BLOB,
            text_content TEXT,
            byte_size INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            parent_id TEXT REFERENCES groups(id) ON DELETE SET NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            hotkey TEXT
        );

        CREATE TABLE clip_groups (
            clip_id TEXT NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
            group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            PRIMARY KEY (clip_id, group_id)
        );

        CREATE TABLE tags (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE
        );

        CREATE TABLE clip_tags (
            clip_id TEXT NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
            tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
            PRIMARY KEY (clip_id, tag_id)
        );

        CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE INDEX idx_clips_hash ON clips(content_hash);
        CREATE INDEX idx_clips_copied ON clips(copied_at DESC);
        CREATE INDEX idx_clips_last_used ON clips(last_used_at DESC);
        CREATE INDEX idx_clips_pinned ON clips(is_pinned, pin_order);
        CREATE INDEX idx_clips_bundle ON clips(source_bundle_id);
        CREATE INDEX idx_clips_type ON clips(primary_type);
        CREATE INDEX idx_clip_formats_clip ON clip_formats(clip_id);

        CREATE VIRTUAL TABLE clips_fts USING fts5(
            clip_id UNINDEXED,
            search_text,
            preview,
            custom_name,
            source_app_name,
            ocr_text,
            group_name,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """
    }

    private var migrationV2: String {
        """
        CREATE INDEX IF NOT EXISTS idx_clips_never_delete ON clips(never_delete);
        """
    }

    public func rebuildFTS() {
        exec("DELETE FROM clips_fts;")
        exec("""
        INSERT INTO clips_fts(clip_id, search_text, preview, custom_name, source_app_name, ocr_text, group_name)
        SELECT c.id, c.search_text, c.preview, COALESCE(c.custom_name,''), COALESCE(c.source_app_name,''),
               COALESCE(c.ocr_text,''), COALESCE(g.name,'')
        FROM clips c
        LEFT JOIN groups g ON g.id = c.group_id;
        """)
    }

    public func integrityCheck() -> String {
        var result = "unknown"
        if let stmt = prepare("PRAGMA integrity_check;") {
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
                result = String(cString: c)
            }
        }
        return result
    }

    public func vacuum() {
        exec("VACUUM;")
        exec("PRAGMA wal_checkpoint(TRUNCATE);")
    }
}

enum SQLiteValue {
    static func string(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let stmt, let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    static func double(_ stmt: OpaquePointer?, _ index: Int32) -> Double {
        sqlite3_column_double(stmt, index)
    }

    static func int(_ stmt: OpaquePointer?, _ index: Int32) -> Int {
        Int(sqlite3_column_int(stmt, index))
    }

    static func int64(_ stmt: OpaquePointer?, _ index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }

    static func data(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        guard let stmt else { return nil }
        let length = Int(sqlite3_column_bytes(stmt, index))
        guard length > 0, let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        return Data(bytes: bytes, count: length)
    }

    static func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    static func bindDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double) {
        sqlite3_bind_double(stmt, index, value)
    }

    static func bindInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int) {
        sqlite3_bind_int(stmt, index, Int32(value))
    }

    static func bindData(_ stmt: OpaquePointer?, _ index: Int32, _ value: Data?) {
        if let value {
            value.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}

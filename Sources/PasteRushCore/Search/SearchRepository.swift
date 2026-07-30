import Foundation
import SQLite3

public struct SearchQuery: Sendable, Equatable {
    public var freeText: String = ""
    public var exactPhrase: String?
    public var typeFilter: ClipPrimaryType?
    public var appFilter: String?
    public var pinnedOnly: Bool?
    public var before: Date?
    public var after: Date?
    public var useRegex: Bool = false
    public var raw: String = ""

    public init(raw: String = "") {
        self.raw = raw
        Self.parse(raw, into: &self)
    }

    public static func parse(_ input: String, into query: inout SearchQuery) {
        query.raw = input
        var remaining = input

        func strip(_ pattern: String, apply: (String) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
            let range = NSRange(remaining.startIndex..., in: remaining)
            let matches = regex.matches(in: remaining, range: range)
            for match in matches.reversed() {
                if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: remaining) {
                    apply(String(remaining[r]))
                }
                if let full = Range(match.range, in: remaining) {
                    remaining.removeSubrange(full)
                }
            }
        }

        strip(#"type:(\w+)"#) { query.typeFilter = ClipPrimaryType(rawValue: $0.lowercased()) }
        strip(#"app:([^\s]+)"#) { query.appFilter = $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        strip(#"pinned:(true|false|1|0|yes|no)"#) { query.pinnedOnly = ["true", "1", "yes"].contains($0.lowercased()) }
        strip(#"before:(\d{4}-\d{2}-\d{2})"#) { query.before = SearchQuery.dateFormatter.date(from: $0) }
        strip(#"after:(\d{4}-\d{2}-\d{2})"#) { query.after = SearchQuery.dateFormatter.date(from: $0) }

        if let phraseRegex = try? NSRegularExpression(pattern: #""([^"]+)""#),
           let match = phraseRegex.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
           let r = Range(match.range(at: 1), in: remaining) {
            query.exactPhrase = String(remaining[r])
            if let full = Range(match.range, in: remaining) {
                remaining.removeSubrange(full)
            }
        }

        query.freeText = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

public final class SearchRepository {
    private let db: Database

    public init(db: Database = .shared) {
        self.db = db
    }

    public func search(_ query: SearchQuery, limit: Int = 200) -> [ClipListItem] {
        db.sync {
            if query.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                query.typeFilter == nil && query.appFilter == nil && query.pinnedOnly == nil &&
                query.before == nil && query.after == nil {
                return ClipRepository(db: db).recent(limit: limit, pinnedOnly: false)
            }

            var whereClauses: [String] = ["1=1"]
            var ftsMatch: String?

            if let phrase = query.exactPhrase, !phrase.isEmpty {
                ftsMatch = "\"\(escapeFTS(phrase))\""
            } else if !query.freeText.isEmpty {
                if query.useRegex {
                    // fallback LIKE + post filter
                    whereClauses.append("c.search_text REGEXP_PLACEHOLDER")
                } else {
                    let tokens = query.freeText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                    let parts = tokens.map { token -> String in
                        let folded = PolishNormalizer.fold(token)
                        let t = escapeFTS(folded)
                        if t.hasSuffix("*") { return t }
                        return "\(t)*"
                    }
                    ftsMatch = parts.joined(separator: " ")
                }
            }

            if let type = query.typeFilter {
                whereClauses.append("c.primary_type = '\(type.rawValue)'")
            }
            if let app = query.appFilter, !app.isEmpty {
                let escaped = app.replacingOccurrences(of: "'", with: "''")
                whereClauses.append("(c.source_app_name LIKE '%\(escaped)%' OR c.source_bundle_id LIKE '%\(escaped)%')")
            }
            if let pinned = query.pinnedOnly {
                whereClauses.append("c.is_pinned = \(pinned ? 1 : 0)")
            }
            if let before = query.before {
                whereClauses.append("c.copied_at < \(before.timeIntervalSince1970)")
            }
            if let after = query.after {
                whereClauses.append("c.copied_at > \(after.timeIntervalSince1970)")
            }

            let sql: String
            if let ftsMatch, !ftsMatch.isEmpty {
                sql = """
                SELECT c.id, c.preview, c.custom_name, c.primary_type, c.source_app_name, c.source_bundle_id,
                       c.copied_at, c.last_used_at, c.use_count, c.is_pinned, c.never_delete, c.group_id, g.name,
                       c.thumbnail_path, c.total_bytes,
                       CASE
                         WHEN c.is_pinned = 1 THEN 0 ELSE 1 END AS rank_pin,
                       CASE
                         WHEN lower(c.preview) = lower('\(escapeSQL(query.freeText))') THEN 0
                         WHEN lower(c.preview) LIKE lower('\(escapeSQL(query.freeText))') || '%' THEN 1
                         ELSE 2 END AS rank_exact,
                       bm25(clips_fts) AS rank_fts
                FROM clips_fts
                JOIN clips c ON c.id = clips_fts.clip_id
                LEFT JOIN groups g ON g.id = c.group_id
                WHERE clips_fts MATCH '\(ftsMatch)' AND \(whereClauses.joined(separator: " AND "))
                ORDER BY rank_pin ASC, rank_exact ASC, rank_fts ASC, c.use_count DESC, c.last_used_at DESC, c.copied_at DESC
                LIMIT \(limit);
                """
            } else {
                sql = """
                SELECT c.id, c.preview, c.custom_name, c.primary_type, c.source_app_name, c.source_bundle_id,
                       c.copied_at, c.last_used_at, c.use_count, c.is_pinned, c.never_delete, c.group_id, g.name,
                       c.thumbnail_path, c.total_bytes
                FROM clips c
                LEFT JOIN groups g ON g.id = c.group_id
                WHERE \(whereClauses.joined(separator: " AND "))
                ORDER BY c.is_pinned DESC, c.pin_order ASC, c.use_count DESC, c.last_used_at DESC, c.copied_at DESC
                LIMIT \(limit);
                """
            }

            var items = [ClipListItem]()
            if ftsMatch != nil {
                items = runFTS(sql: sql)
            } else {
                items = ClipRepository(db: db).mapList(sql)
            }

            // Fallback LIKE for diacritic-folded / partial matches when FTS returns nothing
            if items.isEmpty, !query.freeText.isEmpty {
                let like = escapeSQL(PolishNormalizer.fold(query.freeText))
                let likeSQL = """
                SELECT c.id, c.preview, c.custom_name, c.primary_type, c.source_app_name, c.source_bundle_id,
                       c.copied_at, c.last_used_at, c.use_count, c.is_pinned, c.never_delete, c.group_id, g.name,
                       c.thumbnail_path, c.total_bytes
                FROM clips c
                LEFT JOIN groups g ON g.id = c.group_id
                WHERE c.search_text LIKE '%\(like)%' AND \(whereClauses.joined(separator: " AND "))
                ORDER BY c.is_pinned DESC, c.use_count DESC, c.last_used_at DESC
                LIMIT \(limit);
                """
                items = ClipRepository(db: db).mapList(likeSQL)
            }

            if query.useRegex, !query.freeText.isEmpty, let regex = try? NSRegularExpression(pattern: query.freeText, options: .caseInsensitive) {
                items = items.filter { item in
                    let target = item.displayTitle
                    return regex.firstMatch(in: target, range: NSRange(target.startIndex..., in: target)) != nil
                }
            }

            return items
        }
    }

    private func runFTS(sql: String) -> [ClipListItem] {
        var items: [ClipListItem] = []
        guard let stmt = db.prepare(sql) else {
            // FTS query may fail on special chars — fall back
            return ClipRepository(db: db).recent(limit: 200)
        }
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

    private func extractSelect(_ sql: String) -> String {
        // For non-FTS mapList compatibility — unused when FTS path uses runFTS
        sql
    }

    private func escapeFTS(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }

    private func escapeSQL(_ input: String) -> String {
        input.replacingOccurrences(of: "'", with: "''")
    }
}

public final class SearchCoordinator: ObservableObject {
    @Published public var query: String = ""
    @Published public var results: [ClipListItem] = []
    @Published public var selectedIndex: Int = 0
    @Published public var isSearching = false
    @Published public var pinnedOnly = false
    @Published public var useRegex = false
    /// Bumped on each popup open so the list remounts at the top.
    @Published public var listSessionID: UInt64 = 0

    private let repository = SearchRepository()
    private var generation: UInt64 = 0
    private let queue = DispatchQueue(label: "com.pasterush.search", qos: .userInteractive)

    public init() {}

    public func reset() {
        query = ""
        selectedIndex = 0
        listSessionID &+= 1
        refresh()
    }

    public func appendText(_ text: String) {
        query += text
        search(query)
    }

    public func deleteBackward() {
        guard !query.isEmpty else { return }
        query.removeLast()
        search(query)
    }

    public func search(_ text: String) {
        query = text
        generation &+= 1
        let token = generation
        isSearching = true
        var parsed = SearchQuery(raw: text)
        parsed.useRegex = useRegex
        if pinnedOnly { parsed.pinnedOnly = true }
        let repo = repository

        queue.async { [weak self] in
            let start = CFAbsoluteTimeGetCurrent()
            let items = repo.search(parsed)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.results = items
                self.selectedIndex = 0
                self.isSearching = false
                if elapsed > 50 {
                    NSLog("PasteRush search took %.1fms for '%@'", elapsed, text)
                }
            }
        }
    }

    public func refresh() {
        search(query)
    }

    public func moveSelection(delta: Int) {
        guard !results.isEmpty else { return }
        let next = selectedIndex + delta
        selectedIndex = max(0, min(results.count - 1, next))
    }

    public func page(delta: Int) {
        moveSelection(delta: delta * 10)
    }

    public var selectedItem: ClipListItem? {
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }
}

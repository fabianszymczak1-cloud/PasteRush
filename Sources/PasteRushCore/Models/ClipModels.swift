import Foundation

public enum ClipPrimaryType: String, Codable, Sendable, CaseIterable {
    case text
    case rtf
    case html
    case url
    case image
    case file
    case color
    case unknown
}

public struct ClipFormat: Codable, Sendable, Equatable {
    public var uti: String
    public var blobPath: String?
    public var inlineData: Data?
    public var textContent: String?
    public var byteSize: Int

    public init(uti: String, blobPath: String? = nil, inlineData: Data? = nil, textContent: String? = nil, byteSize: Int = 0) {
        self.uti = uti
        self.blobPath = blobPath
        self.inlineData = inlineData
        self.textContent = textContent
        self.byteSize = byteSize
    }
}

public struct ClipRecord: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var copiedAt: Date
    public var lastUsedAt: Date
    public var useCount: Int
    public var primaryType: ClipPrimaryType
    public var searchText: String
    public var preview: String
    public var contentHash: String
    public var totalBytes: Int
    public var sourceAppName: String?
    public var sourceBundleId: String?
    public var sourceWindowTitle: String?
    public var isPinned: Bool
    public var neverDelete: Bool
    public var pinOrder: Int
    public var customName: String?
    public var customHotkey: String?
    public var groupId: String?
    public var thumbnailPath: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var ocrText: String?
    public var formats: [ClipFormat]

    public init(
        id: String = UUID().uuidString,
        copiedAt: Date = Date(),
        lastUsedAt: Date = Date(),
        useCount: Int = 0,
        primaryType: ClipPrimaryType = .text,
        searchText: String = "",
        preview: String = "",
        contentHash: String = "",
        totalBytes: Int = 0,
        sourceAppName: String? = nil,
        sourceBundleId: String? = nil,
        sourceWindowTitle: String? = nil,
        isPinned: Bool = false,
        neverDelete: Bool = false,
        pinOrder: Int = 0,
        customName: String? = nil,
        customHotkey: String? = nil,
        groupId: String? = nil,
        thumbnailPath: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        ocrText: String? = nil,
        formats: [ClipFormat] = []
    ) {
        self.id = id
        self.copiedAt = copiedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.primaryType = primaryType
        self.searchText = searchText
        self.preview = preview
        self.contentHash = contentHash
        self.totalBytes = totalBytes
        self.sourceAppName = sourceAppName
        self.sourceBundleId = sourceBundleId
        self.sourceWindowTitle = sourceWindowTitle
        self.isPinned = isPinned
        self.neverDelete = neverDelete
        self.pinOrder = pinOrder
        self.customName = customName
        self.customHotkey = customHotkey
        self.groupId = groupId
        self.thumbnailPath = thumbnailPath
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.ocrText = ocrText
        self.formats = formats
    }
}

public struct ClipGroup: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var parentId: String?
    public var sortOrder: Int
    public var hotkey: String?

    public init(id: String = UUID().uuidString, name: String, parentId: String? = nil, sortOrder: Int = 0, hotkey: String? = nil) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.sortOrder = sortOrder
        self.hotkey = hotkey
    }
}

public struct ClipListItem: Identifiable, Sendable, Equatable {
    public var id: String
    public var preview: String
    public var customName: String?
    public var primaryType: ClipPrimaryType
    public var sourceAppName: String?
    public var sourceBundleId: String?
    public var copiedAt: Date
    public var lastUsedAt: Date
    public var useCount: Int
    public var isPinned: Bool
    public var neverDelete: Bool
    public var groupId: String?
    public var groupName: String?
    public var thumbnailPath: String?
    public var totalBytes: Int
    public var highlightRanges: [Range<String.Index>]?

    public init(
        id: String,
        preview: String,
        customName: String? = nil,
        primaryType: ClipPrimaryType,
        sourceAppName: String? = nil,
        sourceBundleId: String? = nil,
        copiedAt: Date,
        lastUsedAt: Date,
        useCount: Int,
        isPinned: Bool,
        neverDelete: Bool = false,
        groupId: String? = nil,
        groupName: String? = nil,
        thumbnailPath: String? = nil,
        totalBytes: Int = 0,
        highlightRanges: [Range<String.Index>]? = nil
    ) {
        self.id = id
        self.preview = preview
        self.customName = customName
        self.primaryType = primaryType
        self.sourceAppName = sourceAppName
        self.sourceBundleId = sourceBundleId
        self.copiedAt = copiedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.isPinned = isPinned
        self.neverDelete = neverDelete
        self.groupId = groupId
        self.groupName = groupName
        self.thumbnailPath = thumbnailPath
        self.totalBytes = totalBytes
        self.highlightRanges = highlightRanges
    }

    public var displayTitle: String {
        if let customName, !customName.isEmpty { return customName }
        return preview
    }
}

public struct DatabaseStats: Sendable, Equatable {
    public var clipCount: Int
    public var databaseBytes: Int64
    public var imageBytes: Int64
    public var freeDiskBytes: Int64

    public init(clipCount: Int, databaseBytes: Int64, imageBytes: Int64, freeDiskBytes: Int64) {
        self.clipCount = clipCount
        self.databaseBytes = databaseBytes
        self.imageBytes = imageBytes
        self.freeDiskBytes = freeDiskBytes
    }
}

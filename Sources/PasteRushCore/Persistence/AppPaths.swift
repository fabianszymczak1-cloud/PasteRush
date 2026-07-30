import Foundation

public enum AppPaths {
    public static let appSupportName = "PasteRush"

    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent(appSupportName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static var databaseURL: URL {
        applicationSupport.appendingPathComponent("pasterush.sqlite")
    }

    public static var blobsDirectory: URL {
        let url = applicationSupport.appendingPathComponent("blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static var thumbnailsDirectory: URL {
        let url = applicationSupport.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static var backupsDirectory: URL {
        let url = applicationSupport.appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func blobURL(clipId: String, uti: String) -> URL {
        let safe = uti.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "/", with: "_")
        return blobsDirectory.appendingPathComponent("\(clipId)_\(safe).bin")
    }

    public static func thumbnailURL(clipId: String) -> URL {
        thumbnailsDirectory.appendingPathComponent("\(clipId).jpg")
    }
}

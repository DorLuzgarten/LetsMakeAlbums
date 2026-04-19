import OSLog

// GPS coordinates and file paths must always use privacy: .sensitive so they
// are redacted in the unified log on non-developer devices.
enum AppLogger {
    static let photos     = Logger(subsystem: "com.dordorel.LetsMakeAlbums", category: "photos")
    static let geocoding  = Logger(subsystem: "com.dordorel.LetsMakeAlbums", category: "geocoding")
    static let clustering = Logger(subsystem: "com.dordorel.LetsMakeAlbums", category: "clustering")
    static let ui         = Logger(subsystem: "com.dordorel.LetsMakeAlbums", category: "ui")
}

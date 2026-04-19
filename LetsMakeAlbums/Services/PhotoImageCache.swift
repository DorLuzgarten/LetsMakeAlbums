import Photos

// Single shared PHCachingImageManager for the whole app.
// One instance avoids fragmented caches between the card grid and the detail sheet.
enum PhotoImageCache {
    static let shared = PHCachingImageManager()
}

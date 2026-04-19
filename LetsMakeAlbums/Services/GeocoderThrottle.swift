import CoreLocation

// Serialises all reverse-geocoding calls and enforces a minimum 1.25 s gap
// between requests (~48 req/min), staying under Apple's ~50 req/min limit.
// A single shared instance is used app-wide via PhotoLibraryManager.
actor GeocoderThrottle {
    private let geocoder = CLGeocoder()
    private var lastRequestDate: Date = .distantPast
    private let minimumInterval: TimeInterval = 1.25

    func reverseGeocode(_ location: CLLocation) async throws -> [CLPlacemark] {
        let elapsed = Date().timeIntervalSince(lastRequestDate)
        if elapsed < minimumInterval {
            try await Task.sleep(for: .seconds(minimumInterval - elapsed))
        }
        lastRequestDate = Date()
        return try await geocoder.reverseGeocodeLocation(location)
    }

    func cancelAll() {
        geocoder.cancelGeocode()
    }
}

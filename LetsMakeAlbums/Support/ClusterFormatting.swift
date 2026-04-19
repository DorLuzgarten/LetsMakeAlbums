//
//  ClusterFormatting.swift
//  LetsMakeAlbums
//
//  Created by Dor Luzgarten on 15/04/2026.
//

import CoreLocation
import Foundation

enum ClusterFormatting {
    static let fullDateWithYear: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMMMMd")
        f.timeStyle = .none
        return f
    }()

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    // DateFormatter and DateIntervalFormatter are not thread-safe;
    // these are accessed only from the main actor via suggestedName.
    private static let smartNameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMMMMd")
        return f
    }()

    private static let smartNameIntervalFormatter: DateIntervalFormatter = {
        let f = DateIntervalFormatter()
        f.dateTemplate = "yMMMMd"
        return f
    }()

    static func dateRange(startDate: Date?, endDate: Date?) -> String {
        guard let startDate else { return "Undated photos" }
        guard let endDate, !Calendar.current.isDate(startDate, inSameDayAs: endDate) else {
            return fullDateWithYear.string(from: startDate)
        }
        return "\(fullDateWithYear.string(from: startDate)) – \(fullDateWithYear.string(from: endDate))"
    }

    static func locationSummary(
        _ location: CLLocation?,
        locationName: String? = nil,
        isGeocoding: Bool = false
    ) -> String {
        if let locationName, !locationName.isEmpty { return locationName }
        if isGeocoding { return "Loading location..." }
        return "Unknown Location"
    }

    static func generateSmartName(
        locationName: String?,
        startDate: Date?,
        endDate: Date?,
        isGeocoding: Bool
    ) -> String {
        if isGeocoding { return "Naming..." }

        let place = locationName ?? "Unknown Location"
        guard let start = startDate, let end = endDate else { return place }

        if end.timeIntervalSince(start) > 86_400 {
            let range = smartNameIntervalFormatter.string(from: start, to: end)
            return "Trip to \(place) – \(range)"
        }
        return "\(place) – \(smartNameDateFormatter.string(from: start))"
    }
}

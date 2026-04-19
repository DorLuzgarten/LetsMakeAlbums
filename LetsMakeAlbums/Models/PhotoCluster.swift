//
//  PhotoCluster.swift
//  LetsMakeAlbums
//
//  Created by Dor Luzgarten on 15/04/2026.
//

import CoreLocation
import Photos
import SwiftUI

// @unchecked Sendable: all mutations are gated through @MainActor PhotoLibraryManager.
// The class itself is not @MainActor so it can be created inside Task.detached during
// the scan phase (before any concurrent access occurs).
@Observable
final class PhotoCluster: Identifiable, @unchecked Sendable {
    let id = UUID()
    var assets: [PHAsset]
    var startDate: Date?
    var endDate: Date?
    var locationName: String?
    var isGeocoding: Bool = false

    var suggestedName: String {
        ClusterFormatting.generateSmartName(
            locationName: locationName,
            startDate: startDate,
            endDate: endDate,
            isGeocoding: isGeocoding
        )
    }

    var photoCount: Int { assets.count }
    var representativeAsset: PHAsset? { assets.first }
    var assetIdentifiers: [String] { assets.map(\.localIdentifier) }

    var representativeLocation: CLLocation? {
        Self.averageLocation(for: assets)
    }

    var namingLocation: CLLocation? {
        assets.compactMap(\.location).first
    }

    init(assets: [PHAsset]) {
        self.assets = assets
        recalculateDateRange()
    }

    func replaceAssets(_ assets: [PHAsset]) {
        self.assets = assets
        recalculateDateRange()
    }

    private func recalculateDateRange() {
        let dates = assets.compactMap(\.creationDate)
        startDate = dates.min()
        endDate = dates.max()
    }

    private static func averageLocation(for assets: [PHAsset]) -> CLLocation? {
        let locations = assets.compactMap(\.location)
        guard !locations.isEmpty else { return nil }
        let total = locations.reduce((lat: 0.0, lon: 0.0)) {
            ($0.lat + $1.coordinate.latitude, $0.lon + $1.coordinate.longitude)
        }
        let count = Double(locations.count)
        return CLLocation(latitude: total.lat / count, longitude: total.lon / count)
    }
}

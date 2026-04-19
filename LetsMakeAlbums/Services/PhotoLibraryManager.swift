//
//  PhotoLibraryManager.swift
//  LetsMakeAlbums
//
//  Created by Dor Luzgarten on 15/04/2026.
//

import CoreLocation
import Foundation
import Observation
import OSLog
import Photos

@MainActor
@Observable
final class PhotoLibraryManager {

    // MARK: - Public types

    enum ProcessingState: Equatable {
        case idle
        case needsPermission
        case requestingPermission
        case scanning
        case ready
        case empty
        case denied
        case failed(String)
    }

    enum AlbumCreationState: Equatable {
        case idle
        case creating
        case created(String)
        case failed(String)
    }

    enum PhotoLibraryError: LocalizedError {
        case albumCreationFailed
        var errorDescription: String? { "Photos did not create the album." }
    }

    // MARK: - Private types

    private enum AlbumCreationResult: Sendable {
        case success
        case failure(String)
    }

    // Sendable snapshot passed into Task.detached for cross-boundary name restoration.
    private struct ClusterNameSnapshot: Sendable {
        let assetIDs: Set<String>
        let startDate: Date?
        let endDate: Date?
        let latitude: Double?
        let longitude: Double?
        let locationName: String?

        var representativeLocation: CLLocation? {
            guard let lat = latitude, let lon = longitude else { return nil }
            return CLLocation(latitude: lat, longitude: lon)
        }

        init(cluster: PhotoCluster) {
            assetIDs = Set(cluster.assetIdentifiers)
            startDate = cluster.startDate
            endDate = cluster.endDate
            let loc = cluster.representativeLocation
            latitude = loc?.coordinate.latitude
            longitude = loc?.coordinate.longitude
            locationName = cluster.locationName
        }
    }

    // MARK: - Observed state

    var processingState: ProcessingState = .idle
    var clusters: [PhotoCluster] = []
    var lastScanDate: Date?
    private(set) var organizedAssetIDs: Set<String> = []

    // MARK: - Private state

    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var geocodingTasks: [PhotoCluster.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var albumCreationTasks: [PhotoCluster.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private let geocoderThrottle = GeocoderThrottle()
    @ObservationIgnored private var locationCache: [String: String] = [:]

    private var albumCreationStates: [PhotoCluster.ID: AlbumCreationState] = [:]
    private let timeThreshold: TimeInterval
    private let locationThreshold: CLLocationDistance
    private let minimumClusterSize: Int

    // MARK: - Lifecycle

    init(
        timeThreshold: TimeInterval = 4 * 60 * 60,
        locationThreshold: CLLocationDistance = 5_000,
        minimumClusterSize: Int = 5
    ) {
        self.timeThreshold = timeThreshold
        self.locationThreshold = locationThreshold
        self.minimumClusterSize = minimumClusterSize
    }

    deinit {
        processingTask?.cancel()
        geocodingTasks.values.forEach { $0.cancel() }
        albumCreationTasks.values.forEach { $0.cancel() }
        Task { [geocoderThrottle] in await geocoderThrottle.cancelAll() }
    }

    // MARK: - Public API

    func prepare() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: scanLibrary()
        case .notDetermined: processingState = .needsPermission
        case .denied, .restricted: processingState = .denied
        @unknown default: processingState = .denied
        }
    }

    func requestAccessAndScan() {
        processingTask?.cancel()
        processingTask = Task { [weak self] in
            guard let self else { return }
            processingState = .requestingPermission
            let status = await requestAuthorization()
            guard status == .authorized || status == .limited else {
                clusters = []
                processingState = .denied
                return
            }
            await performScan()
        }
    }

    func scanLibrary() {
        processingTask?.cancel()
        processingTask = Task { [weak self] in
            await self?.performScan()
        }
    }

    func state(for cluster: PhotoCluster) -> AlbumCreationState {
        albumCreationStates[cluster.id] ?? .idle
    }

    func createAlbum(for cluster: PhotoCluster, title: String? = nil) {
        guard state(for: cluster) != .creating else { return }

        let clusterID = cluster.id
        let albumName = sanitizedAlbumName(title) ?? cluster.suggestedName
        let assetIdentifiers = cluster.assetIdentifiers
        let assetIdentifierSet = Set(assetIdentifiers)
        albumCreationStates[clusterID] = .creating

        albumCreationTasks[clusterID]?.cancel()
        albumCreationTasks[clusterID] = Task { [weak self] in
            let result = await Self.createAlbumResult(named: albumName, assetIdentifiers: assetIdentifiers)
            guard let self else { return }
            albumCreationTasks[clusterID] = nil
            switch result {
            case .success:
                albumCreationStates[clusterID] = .created(albumName)
                organizedAssetIDs.formUnion(assetIdentifierSet)
                removeOrganizedAssetsFromSuggestions(assetIdentifierSet)
            case let .failure(message):
                albumCreationStates[clusterID] = .failed(message)
            }
        }
    }

    func mergeClusters(draggedID: String, targetID: String) {
        guard draggedID != targetID,
              let draggedIndex = clusters.firstIndex(where: { $0.id.uuidString == draggedID }),
              let targetIndex = clusters.firstIndex(where: { $0.id.uuidString == targetID }) else { return }

        let draggedCluster = clusters[draggedIndex]
        let targetCluster = clusters[targetIndex]
        let mergedAssets = (targetCluster.assets + draggedCluster.assets).sorted(by: Self.sortAssetsChronologically)

        targetCluster.replaceAssets(mergedAssets)
        clusters.remove(at: draggedIndex)
        albumCreationStates[draggedCluster.id] = nil
        processingState = clusters.isEmpty ? .empty : .ready

        applyCachedLocationName(for: targetCluster.id)
    }

    func dismissCluster(id clusterID: PhotoCluster.ID?) {
        guard let clusterID,
              let index = clusters.firstIndex(where: { $0.id == clusterID }) else { return }

        clusters.remove(at: index)
        albumCreationStates[clusterID] = nil
        albumCreationTasks[clusterID]?.cancel()
        albumCreationTasks[clusterID] = nil
        geocodingTasks[clusterID]?.cancel()
        geocodingTasks[clusterID] = nil
        processingState = clusters.isEmpty ? .empty : .ready
    }

    func resolveLocationName(for clusterID: PhotoCluster.ID) {
        guard let index = clusters.firstIndex(where: { $0.id == clusterID }) else { return }

        let cluster = clusters[index]
        guard cluster.locationName == nil || cluster.locationName == Self.unknownLocationName else { return }

        guard let location = cluster.namingLocation else {
            finishGeocodingWithoutPlace(for: clusterID)
            return
        }

        let cacheKey = Self.locationCacheKey(for: location)
        if let cached = locationCache[cacheKey] {
            setLocationName(cached, for: clusterID)
            return
        }

        guard geocodingTasks[clusterID] == nil else { return }
        clusters[index].isGeocoding = true

        geocodingTasks[clusterID] = Task { [weak self] in
            guard let self else { return }
            let name = await placeName(for: location)

            geocodingTasks[clusterID] = nil
            guard !Task.isCancelled else { return }

            if let name {
                locationCache[cacheKey] = name
                setLocationName(name, for: clusterID)
            } else {
                finishGeocodingWithoutPlace(for: clusterID)
            }
        }
    }

    // MARK: - Private: scan (heavy work runs off main actor)

    private func performScan() async {
        processingState = .scanning
        geocodingTasks.values.forEach { $0.cancel() }
        geocodingTasks = [:]

        // Snapshot main-actor state before crossing to the detached task.
        let previousSnapshots = clusters.map(ClusterNameSnapshot.init)
        let locationCacheSnapshot = locationCache
        let timeThreshold = self.timeThreshold
        let locationThreshold = self.locationThreshold
        let minimumClusterSize = self.minimumClusterSize

        let (scannedOrganizedIDs, scannedClusters) = await Task.detached(priority: .userInitiated) {
            let organizedIDs = Self.fetchOrganizedAssetIDs()
            let assets = Self.fetchImageAssets(excluding: organizedIDs)
            var newClusters = Self.makeClusters(
                from: assets,
                timeThreshold: timeThreshold,
                locationThreshold: locationThreshold,
                minimumClusterSize: minimumClusterSize
            )
            Self.restoreLocationNames(
                in: &newClusters,
                from: previousSnapshots,
                cache: locationCacheSnapshot,
                locationThreshold: locationThreshold,
                timeThreshold: timeThreshold
            )
            return (organizedIDs, newClusters)
        }.value

        guard !Task.isCancelled else { return }

        organizedAssetIDs = scannedOrganizedIDs
        clusters = scannedClusters
        lastScanDate = Date()
        albumCreationStates = [:]
        processingState = clusters.isEmpty ? .empty : .ready
    }

    // MARK: - Private: nonisolated scan operations

    private nonisolated static func fetchOrganizedAssetIDs() -> Set<String> {
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var ids = Set<String>()
        collections.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            ids.reserveCapacity(ids.count + assets.count)
            assets.enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        }
        return ids
    }

    private nonisolated static func fetchImageAssets(excluding organizedIDs: Set<String>) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: #keyPath(PHAsset.creationDate), ascending: true)]

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            guard !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
            guard !organizedIDs.contains(asset.localIdentifier) else { return }
            assets.append(asset)
        }
        return assets  // already sorted by PHFetchOptions sortDescriptors
    }

    private nonisolated static func makeClusters(
        from assets: [PHAsset],
        timeThreshold: TimeInterval,
        locationThreshold: CLLocationDistance,
        minimumClusterSize: Int
    ) -> [PhotoCluster] {
        var groups: [[PHAsset]] = []
        var current: [PHAsset] = []
        var previous: PHAsset?

        for asset in assets {
            if let previous,
               shouldSplit(previous: previous, current: asset,
                           timeThreshold: timeThreshold, locationThreshold: locationThreshold) {
                if current.count >= minimumClusterSize { groups.append(current) }
                current.removeAll(keepingCapacity: true)
            }
            current.append(asset)
            previous = asset
        }
        if current.count >= minimumClusterSize { groups.append(current) }
        return groups.map(PhotoCluster.init(assets:))
    }

    private nonisolated static func shouldSplit(
        previous: PHAsset,
        current: PHAsset,
        timeThreshold: TimeInterval,
        locationThreshold: CLLocationDistance
    ) -> Bool {
        guard let prev = previous.creationDate, let cur = current.creationDate else { return false }
        if abs(cur.timeIntervalSince(prev)) > timeThreshold { return true }
        if let p = previous.location, let c = current.location,
           c.distance(from: p) > locationThreshold { return true }
        return false
    }

    // Merges the former preserveResolvedNames + applyCachedLocationNames into one pass.
    private nonisolated static func restoreLocationNames(
        in clusters: inout [PhotoCluster],
        from snapshots: [ClusterNameSnapshot],
        cache: [String: String],
        locationThreshold: CLLocationDistance,
        timeThreshold: TimeInterval
    ) {
        let resolved = snapshots.filter {
            guard let name = $0.locationName?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !name.isEmpty && name != unknownLocationName
        }

        for i in clusters.indices {
            guard clusters[i].locationName == nil || clusters[i].locationName == unknownLocationName else { continue }

            if let loc = clusters[i].namingLocation, let cached = cache[locationCacheKey(for: loc)] {
                clusters[i].locationName = cached
                clusters[i].isGeocoding = false
                continue
            }

            if let match = resolved.first(where: {
                isSameCluster(clusters[i], snapshot: $0,
                              locationThreshold: locationThreshold, timeThreshold: timeThreshold)
            }), let name = match.locationName {
                clusters[i].locationName = name
                clusters[i].isGeocoding = false
            }
        }
    }

    private nonisolated static func isSameCluster(
        _ cluster: PhotoCluster,
        snapshot s: ClusterNameSnapshot,
        locationThreshold: CLLocationDistance,
        timeThreshold: TimeInterval
    ) -> Bool {
        if cluster.assetIdentifiers.contains(where: { s.assetIDs.contains($0) }) { return true }
        guard let cLoc = cluster.representativeLocation,
              let sLoc = s.representativeLocation,
              cLoc.distance(from: sLoc) <= locationThreshold else { return false }
        guard let cStart = cluster.startDate, let cEnd = cluster.endDate,
              let sStart = s.startDate, let sEnd = s.endDate else { return false }
        return cStart.addingTimeInterval(-timeThreshold) <= sEnd &&
               sStart <= cEnd.addingTimeInterval(timeThreshold)
    }

    // MARK: - Private: main-actor helpers

    private func requestAuthorization() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { continuation.resume(returning: $0) }
        }
    }

    private func removeOrganizedAssetsFromSuggestions(_ assetIDs: Set<String>) {
        guard !assetIDs.isEmpty else { return }

        let remainingAssets = clusters.flatMap(\.assets).filter { !assetIDs.contains($0.localIdentifier) }
        let previousSnapshots = clusters.map(ClusterNameSnapshot.init)
        let locationCacheSnapshot = locationCache

        var updated = Self.makeClusters(
            from: remainingAssets,
            timeThreshold: timeThreshold,
            locationThreshold: locationThreshold,
            minimumClusterSize: minimumClusterSize
        )
        Self.restoreLocationNames(
            in: &updated,
            from: previousSnapshots,
            cache: locationCacheSnapshot,
            locationThreshold: locationThreshold,
            timeThreshold: timeThreshold
        )

        clusters = updated

        let activeIDs = Set(clusters.map(\.id))
        albumCreationStates = albumCreationStates.filter { id, state in
            if activeIDs.contains(id) { return true }
            if case .created = state { return true }
            return false
        }
        processingState = clusters.isEmpty ? .empty : .ready
    }

    private func applyCachedLocationName(for clusterID: PhotoCluster.ID) {
        guard let index = clusters.firstIndex(where: { $0.id == clusterID }),
              clusters[index].locationName == nil || clusters[index].locationName == Self.unknownLocationName,
              let location = clusters[index].namingLocation,
              let name = locationCache[Self.locationCacheKey(for: location)] else { return }
        setLocationName(name, for: clusterID)
    }

    private func setLocationName(_ name: String, for clusterID: PhotoCluster.ID) {
        guard let index = clusters.firstIndex(where: { $0.id == clusterID }) else { return }
        clusters[index].locationName = name
        clusters[index].isGeocoding = false
    }

    private func finishGeocodingWithoutPlace(for clusterID: PhotoCluster.ID) {
        guard let index = clusters.firstIndex(where: { $0.id == clusterID }) else { return }
        clusters[index].locationName = Self.unknownLocationName
        clusters[index].isGeocoding = false
    }

    private func placeName(for location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoderThrottle.reverseGeocode(location)
            return placemarks.lazy.compactMap(Self.preferredPlaceName).first
        } catch {
            AppLogger.geocoding.error("Reverse geocoding failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private: nonisolated helpers

    private nonisolated static func preferredPlaceName(from placemark: CLPlacemark) -> String? {
        [placemark.locality, placemark.name, placemark.administrativeArea, placemark.country]
            .compactMap { name -> String? in
                let t = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return t.isEmpty ? nil : t
            }
            .first
    }

    private nonisolated static func locationCacheKey(for location: CLLocation) -> String {
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        return String(format: "%.2f,%.2f", lat, lon)
    }

    private nonisolated static var unknownLocationName: String { "Unknown Location" }

    private nonisolated static func sortAssetsChronologically(_ lhs: PHAsset, _ rhs: PHAsset) -> Bool {
        switch (lhs.creationDate, rhs.creationDate) {
        case let (l?, r?): return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.localIdentifier < rhs.localIdentifier
        }
    }

    private func sanitizedAlbumName(_ name: String?) -> String? {
        let t = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    private nonisolated static func createAlbumResult(
        named title: String,
        assetIdentifiers: [String]
    ) async -> AlbumCreationResult {
        do {
            try await createAlbum(named: title, assetIdentifiers: assetIdentifiers)
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private nonisolated static func createAlbum(named title: String, assetIdentifiers: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                let result = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
                request.addAssets(result)
            } completionHandler: { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: PhotoLibraryError.albumCreationFailed) }
            }
        }
    }
}

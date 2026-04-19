//
//  ClusterDetailView.swift
//  LetsMakeAlbums
//
//  Created by Dor Luzgarten on 15/04/2026.
//

import Photos
import SwiftUI

struct ClusterDetailView: View {
    let cluster: PhotoCluster
    let photoManager: PhotoLibraryManager

    @Environment(\.dismiss) private var dismiss
    @State private var albumName = ""
    @State private var hasEditedAlbumName = false

    private let columns = [
        GridItem(.adaptive(minimum: 112, maximum: 160), spacing: 12)
    ]

    private var displayedCluster: PhotoCluster {
        photoManager.clusters.first { $0.id == cluster.id } ?? cluster
    }

    private var albumState: PhotoLibraryManager.AlbumCreationState {
        photoManager.state(for: displayedCluster)
    }

    private var trimmedAlbumName: String {
        albumName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreateAlbum: Bool {
        guard !trimmedAlbumName.isEmpty else {
            return false
        }

        switch albumState {
        case .idle, .failed:
            return true
        case .creating, .created:
            return false
        }
    }

    var body: some View {
        let cluster = displayedCluster

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summaryHeader(for: cluster)
                albumControls(for: cluster)
                photosSection(for: cluster)
            }
            .padding(24)
        }
        .background(.background)
        .navigationTitle("Preview Album")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .onAppear {
            photoManager.resolveLocationName(for: displayedCluster.id)
            syncAlbumNameIfNeeded(force: true)
        }
        .onChange(of: displayedCluster.suggestedName) {
            syncAlbumNameIfNeeded(force: false)
        }
    }

    private func summaryHeader(for cluster: PhotoCluster) -> some View {
        HStack(alignment: .bottom, spacing: 18) {
            ThumbnailImageView(asset: cluster.representativeAsset)
                .frame(width: 180, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28))
                }

            VStack(alignment: .leading, spacing: 12) {
                Text(cluster.suggestedName)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 14) {
                    Label(ClusterFormatting.dateRange(startDate: cluster.startDate, endDate: cluster.endDate), systemImage: "calendar")

                    Label("\(cluster.photoCount) photos", systemImage: "photo.stack.fill")
                        .monospacedDigit()

                    Label(
                        ClusterFormatting.locationSummary(
                            cluster.representativeLocation,
                            locationName: cluster.locationName,
                            isGeocoding: cluster.isGeocoding
                        ),
                        systemImage: cluster.isGeocoding ? "location.magnifyingglass" : "mappin.and.ellipse"
                    )
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private func albumControls(for cluster: PhotoCluster) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Album Name")
                        .font(.headline)

                    Text("Edit the title before saving this suggestion to Photos.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            TextField("Album Name", text: albumNameBinding)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createAlbumIfPossible)

            HStack {
                statusView(for: cluster)

                Spacer()

                Button(action: createAlbumIfPossible) {
                    createAlbumLabel
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreateAlbum)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.22))
        }
    }

    private func photosSection(for cluster: PhotoCluster) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos")
                    .font(.title2.weight(.semibold))

                Spacer()

                Text("\(cluster.photoCount)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(cluster.assets, id: \.localIdentifier) { asset in
                    DetailThumbnailImageView(asset: asset)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.2))
                        }
                }
            }
        }
    }

    private var albumNameBinding: Binding<String> {
        Binding {
            albumName
        } set: { newValue in
            albumName = newValue
            hasEditedAlbumName = true
        }
    }

    @ViewBuilder
    private func statusView(for cluster: PhotoCluster) -> some View {
        switch albumState {
        case .idle:
            if cluster.isGeocoding {
                Label("Finding a better location name...", systemImage: "location.magnifyingglass")
                    .foregroundStyle(.secondary)
            } else {
                Text("Review the photos, edit the name, then create the album.")
                    .foregroundStyle(.secondary)
            }
        case .creating:
            Label("Creating album...", systemImage: "progress.indicator")
                .foregroundStyle(.secondary)
        case let .created(albumName):
            Label("Created \(albumName)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var createAlbumLabel: some View {
        switch albumState {
        case .creating:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Creating...")
            }
        case let .created(albumName):
            Label("Created", systemImage: "checkmark.circle.fill")
                .help(albumName)
        case .idle, .failed:
            Label("Create Album", systemImage: "plus.rectangle.on.folder")
        }
    }

    private func syncAlbumNameIfNeeded(force: Bool) {
        guard force || !hasEditedAlbumName else {
            return
        }

        albumName = displayedCluster.suggestedName
        hasEditedAlbumName = false
    }

    private func createAlbumIfPossible() {
        guard canCreateAlbum else {
            return
        }

        albumName = trimmedAlbumName
        photoManager.createAlbum(for: displayedCluster, title: trimmedAlbumName)
    }
}

private struct DetailThumbnailImageView: View {
    let asset: PHAsset

    @State private var image: NSImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .clipped()
        .task(id: asset.localIdentifier) {
            requestThumbnail()
        }
        .onDisappear {
            cancelRequest()
        }
    }

    private func requestThumbnail() {
        cancelRequest()
        image = nil

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let targetSize = CGSize(width: 200 * scale, height: 200 * scale)
        let requestedID = asset.localIdentifier

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false

        requestID = PhotoImageCache.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            guard let image else { return }
            if (info?[PHImageCancelledKey] as? Bool) == true { return }
            Task { @MainActor in
                guard self.asset.localIdentifier == requestedID else { return }
                self.image = image
            }
        }
    }

    private func cancelRequest() {
        if let requestID {
            PhotoImageCache.shared.cancelImageRequest(requestID)
        }
        requestID = nil
    }
}

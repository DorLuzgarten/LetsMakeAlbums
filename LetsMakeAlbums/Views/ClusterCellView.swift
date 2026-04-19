//
//  ClusterCellView.swift
//  LetsMakeAlbums
//
//  Created by Dor Luzgarten on 15/04/2026.
//

import SwiftUI

struct ClusterCellView: View {
    let cluster: PhotoCluster
    let albumState: PhotoLibraryManager.AlbumCreationState
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailHeader

            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                footer
            }
            .padding(14)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(borderStyle, lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: .black.opacity(isHovered ? 0.18 : 0.08), radius: isHovered ? 18 : 8, y: isHovered ? 9 : 4)
        .scaleEffect(isHovered ? 1.015 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var thumbnailHeader: some View {
        ZStack(alignment: .bottomLeading) {
            ThumbnailImageView(asset: cluster.representativeAsset)
                .frame(height: 178)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.46)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(alignment: .lastTextBaseline) {
                Label("\(cluster.photoCount)", systemImage: "photo.stack.fill")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                Spacer()

                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
            .foregroundStyle(.white)
            .padding(12)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 8))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(ClusterFormatting.dateRange(startDate: cluster.startDate, endDate: cluster.endDate))
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .lineLimit(2)
            } icon: {
                Image(systemName: "calendar")
                    .symbolRenderingMode(.hierarchical)
            }

            Label(
                ClusterFormatting.locationSummary(
                    cluster.representativeLocation,
                    locationName: cluster.locationName,
                    isGeocoding: cluster.isGeocoding
                ),
                systemImage: cluster.isGeocoding ? "location.magnifyingglass" : "mappin.and.ellipse"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            albumStatusView
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Review")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
        }
    }

    private var borderStyle: some ShapeStyle {
        isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(nsColor: .separatorColor).opacity(isHovered ? 0.38 : 0.18))
    }

    @ViewBuilder
    private var albumStatusView: some View {
        switch albumState {
        case .idle:
            if cluster.isGeocoding {
                Label(cluster.suggestedName, systemImage: "location.magnifyingglass")
                    .lineLimit(1)
            } else {
                Text(cluster.suggestedName)
                    .lineLimit(1)
            }
        case .creating:
            Label("Creating...", systemImage: "progress.indicator")
        case let .created(albumName):
            Label(albumName, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(1)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }
}

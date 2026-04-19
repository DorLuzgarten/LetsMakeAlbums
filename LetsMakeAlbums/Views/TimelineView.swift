import Photos
import SwiftUI

// MARK: - TimelineView

struct TimelineView: View {
    let clusters: [PhotoCluster]
    let selectedClusterID: PhotoCluster.ID?
    let onSelect: (PhotoCluster) -> Void
    let onMerge: (_ draggedID: String, _ targetID: String) -> Void

    // Layout constants mirrored from the design (points ≈ design pixels at 1×).
    private let spineX: CGFloat = 54      // spine center from leading edge
    private let contentLeading: CGFloat = 76 // cluster content indent

    private struct MonthGroup: Identifiable {
        let id: String         // "April 2026"
        var clusters: [PhotoCluster]
        var totalPhotos: Int { clusters.reduce(0) { $0 + $1.photoCount } }
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private var monthGroups: [MonthGroup] {
        var groups: [MonthGroup] = []
        for cluster in clusters {
            let key = cluster.startDate.map { Self.monthFormatter.string(from: $0) } ?? "Unknown"
            if let idx = groups.firstIndex(where: { $0.id == key }) {
                groups[idx].clusters.append(cluster)
            } else {
                groups.append(MonthGroup(id: key, clusters: [cluster]))
            }
        }
        return groups
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hintBar
                    .padding(.horizontal, 40)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 32) {
                    ForEach(monthGroups) { group in
                        monthGroupView(group)
                    }
                }
                .padding(.leading, contentLeading)
                .padding(.trailing, 40)
                .padding(.top, 16)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .topLeading) {
                    spineOverlay
                }
            }
        }
    }

    // MARK: - Spine

    // Full-height vertical line. Placed in .background so it sizes to
    // the VStack height naturally.
    private var spineOverlay: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: spineX - 0.5)
            Color(nsColor: .separatorColor)
                .opacity(0.55)
                .frame(width: 1)
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 36)
    }

    // MARK: - Hint bar

    private var hintBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 11))
            Text("Drag any cluster onto another to merge them into one album.")
                .font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(Color(red: 0.471, green: 0.467, blue: 0.455))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.945, green: 0.945, blue: 0.937))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(red: 0.890, green: 0.886, blue: 0.878), lineWidth: 1)
        )
    }

    // MARK: - Month group

    private func monthGroupView(_ group: MonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            monthHeader(group)
            VStack(spacing: 8) {
                ForEach(group.clusters) { cluster in
                    TimelineEntryView(
                        cluster: cluster,
                        isSelected: selectedClusterID == cluster.id,
                        onSelect: { onSelect(cluster) },
                        onMerge: onMerge
                    )
                }
            }
        }
    }

    private func monthHeader(_ group: MonthGroup) -> some View {
        HStack(spacing: 10) {
            // Node dot centered on spine.
            // contentLeading=76 puts content at x=76. spineX=54 means
            // the node center should be at x=54. Node is 10pt wide,
            // so left edge at 49pt. Offset from content leading: 49-76 = -27.
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(Circle().stroke(Color(nsColor: .tertiaryLabelColor), lineWidth: 1.5))
                .frame(width: 10, height: 10)

            Text(group.id.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            Color(nsColor: .separatorColor)
                .opacity(0.7)
                .frame(height: 1)

            Text(monthCountLabel(group))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .offset(x: -(contentLeading - spineX + 5)) // pull left so node lands on spine
    }

    private func monthCountLabel(_ group: MonthGroup) -> String {
        let p = group.totalPhotos
        let c = group.clusters.count
        return "\(p.formatted()) \(p == 1 ? "photo" : "photos") · \(c) \(c == 1 ? "cluster" : "clusters")"
    }
}

// MARK: - TimelineEntryView

private struct TimelineEntryView: View {
    let cluster: PhotoCluster
    let isSelected: Bool
    let onSelect: () -> Void
    let onMerge: (String, String) -> Void

    @State private var isHovering = false
    @State private var isDropTarget = false

    private var isMultiDay: Bool {
        guard let start = cluster.startDate, let end = cluster.endDate else { return false }
        return !Calendar.current.isDate(start, inSameDayAs: end)
    }

    private var startDay: String {
        cluster.startDate.map { "\(Calendar.current.component(.day, from: $0))" } ?? "—"
    }

    private var endDay: String {
        cluster.endDate.map { "\(Calendar.current.component(.day, from: $0))" } ?? "—"
    }

    private var locationDisplay: String {
        if cluster.isGeocoding { return "Locating…" }
        return cluster.locationName ?? "Unknown Location"
    }

    // MARK: Body

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 20) {
                leadSection
                    .frame(width: 200, alignment: .leading)
                filmStrip
                    .frame(maxWidth: .infinity, alignment: .trailing)
                chevron
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(entryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(entryBorderColor, lineWidth: isDropTarget ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .draggable(cluster.id.uuidString)
        .dropDestination(for: String.self) { draggedIDs, _ in
            guard let id = draggedIDs.first, id != cluster.id.uuidString else { return false }
            withAnimation(.easeInOut(duration: 0.2)) { onMerge(id, cluster.id.uuidString) }
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    // MARK: Sections

    private var leadSection: some View {
        HStack(spacing: 14) {
            dayMarker
                .frame(width: 60, alignment: .leading)
            metaBlock
        }
    }

    private var dayMarker: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(startDay)
                .font(.system(size: 24, weight: .medium).monospacedDigit())
            if isMultiDay {
                Text("–")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                Text(endDay)
                    .font(.system(size: 24, weight: .medium).monospacedDigit())
            }
        }
        .foregroundStyle(.primary)
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(locationDisplay)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "mappin")
                    .font(.system(size: 9))
                Text("\(cluster.photoCount) photos")
                    .monospacedDigit()
                if isMultiDay {
                    Text("·").foregroundStyle(.tertiary)
                    tripBadge
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private var tripBadge: some View {
        Text("Trip")
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(Color(red: 0.471, green: 0.467, blue: 0.455))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(red: 0.945, green: 0.945, blue: 0.937), in: Capsule())
    }

    private var filmStrip: some View {
        HStack(spacing: 3) {
            ForEach(cluster.assets.prefix(6), id: \.localIdentifier) { asset in
                ThumbnailImageView(asset: asset)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            if cluster.photoCount > 6 {
                overflowBadge
            }
        }
    }

    private var overflowBadge: some View {
        Text("+\(cluster.photoCount - 6)")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(red: 0.471, green: 0.467, blue: 0.455))
            .frame(width: 52, height: 52)
            .background(Color(red: 0.945, green: 0.945, blue: 0.937))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary.opacity(isHovering && !isDropTarget ? 1 : 0.3))
            .frame(width: 14)
    }

    // MARK: Appearance helpers

    private var entryBackground: Color {
        if isDropTarget { return Color.accentColor.opacity(0.06) }
        if isHovering   { return Color(nsColor: .controlBackgroundColor) }
        return Color(nsColor: .windowBackgroundColor)
    }

    private var entryBorderColor: Color {
        if isDropTarget { return Color.accentColor.opacity(0.45) }
        if isHovering   { return Color(nsColor: .separatorColor) }
        return Color(nsColor: .separatorColor).opacity(0.5)
    }
}

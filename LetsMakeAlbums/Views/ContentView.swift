//
//  ContentView.swift
//  LetsMakeAlbums
//
//  Created by Dor Luzgarten on 15/04/2026.
//

import Photos
import SwiftUI

struct ContentView: View {
    @State private var photoManager = PhotoLibraryManager()
    @State private var selectedClusterID: PhotoCluster.ID?
    @State private var presentedCluster: PhotoCluster?
    @FocusState private var isGridFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                switch photoManager.processingState {
                case .idle:
                    permissionPrompt
                case .needsPermission:
                    permissionPrompt
                case .requestingPermission:
                    loadingView("Requesting photo access...")
                case .scanning:
                    loadingView("Scanning your photo library...")
                case .ready:
                    resultsView
                case .empty:
                    emptyResultsView
                case .denied:
                    deniedView
                case let .failed(message):
                    errorView(message)
                }
            }
            .navigationTitle("Let's Make Albums")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        photoManager.scanLibrary()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(!canRescan)

                    Button {
                        dismissSelectedCluster()
                    } label: {
                        Label("Dismiss Suggestion", systemImage: "trash")
                    }
                    .disabled(!canDismissSelection)
                    .keyboardShortcut(.delete, modifiers: [])

                    if canRequestAccess {
                        Button {
                            photoManager.requestAccessAndScan()
                        } label: {
                            Label("Grant Access", systemImage: "photo.on.rectangle.angled")
                        }
                        .disabled(photoManager.processingState == .requestingPermission || photoManager.processingState == .scanning)
                    }
                }
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .sheet(item: $presentedCluster) { cluster in
            NavigationStack {
                ClusterDetailView(cluster: cluster, photoManager: photoManager)
            }
            .frame(minWidth: 820, minHeight: 640)
        }
        .task {
            photoManager.prepare()
        }
    }

    private var canRescan: Bool {
        switch photoManager.processingState {
        case .ready, .empty, .failed: true
        default: false
        }
    }

    private var canDismissSelection: Bool {
        guard let selectedClusterID else { return false }
        return photoManager.clusters.contains { $0.id == selectedClusterID }
    }

    private var canRequestAccess: Bool {
        switch photoManager.processingState {
        case .idle, .needsPermission, .denied: true
        default: false
        }
    }

    private var permissionPrompt: some View {
        ContentUnavailableView {
            Label("Find Albums Hiding in Your Library", systemImage: "sparkles.rectangle.stack")
        } description: {
            Text("LetsMakeAlbums scans image metadata on this Mac, skips screenshots, and groups related photos by time and place.")
        } actions: {
            Button("Grant Photo Access") {
                photoManager.requestAccessAndScan()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 40)
                .padding(.top, 22)
                .padding(.bottom, 18)

            TimelineView(
                clusters: photoManager.clusters,
                selectedClusterID: selectedClusterID,
                onSelect: { cluster in
                    selectedClusterID = cluster.id
                    presentedCluster = cluster
                },
                onMerge: { draggedID, targetID in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        photoManager.mergeClusters(draggedID: draggedID, targetID: targetID)
                    }
                }
            )
        }
        .focusable()
        .focused($isGridFocused)
        .onAppear { isGridFocused = true }
        .onDeleteCommand(perform: dismissSelectedCluster)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested Albums")
                    .font(.largeTitle.weight(.semibold))

                Text(summaryText)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                photoManager.scanLibrary()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
        }
    }

    private var summaryText: String {
        let clusterCount = photoManager.clusters.count
        let photoCount = photoManager.clusters.reduce(0) { $0 + $1.photoCount }
        let clusterLabel = clusterCount == 1 ? "cluster" : "clusters"
        let photoLabel = photoCount == 1 ? "photo" : "photos"

        if let lastScanDate = photoManager.lastScanDate {
            return "\(clusterCount) \(clusterLabel), \(photoCount) \(photoLabel) – scanned \(lastScanDate.formatted(date: .abbreviated, time: .shortened))"
        }

        return "\(clusterCount) \(clusterLabel), \(photoCount) \(photoLabel)"
    }

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text(message)
                .font(.headline)

            Text("Large libraries can take a moment.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var emptyResultsView: some View {
        ContentUnavailableView {
            Label("No Album Suggestions Yet", systemImage: "rectangle.stack.badge.minus")
        } description: {
            Text("The scan did not find any non-screenshot groups with at least five photos inside the time and location thresholds.")
        } actions: {
            Button("Scan Again") { photoManager.scanLibrary() }
        }
        .padding()
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Photo Access Needed", systemImage: "lock.rectangle.stack")
        } description: {
            Text("Allow Photos access in System Settings to scan your local library and create albums.")
        } actions: {
            Button("Try Again") { photoManager.requestAccessAndScan() }
        }
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Scan Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { photoManager.scanLibrary() }
        }
        .padding()
    }

    private func dismissSelectedCluster() {
        guard let selectedClusterID else { return }

        let fallbackSelection = photoManager.clusters.first { $0.id != selectedClusterID }?.id
        withAnimation(.easeInOut(duration: 0.2)) {
            photoManager.dismissCluster(id: selectedClusterID)
        }

        if presentedCluster?.id == selectedClusterID {
            presentedCluster = nil
        }

        self.selectedClusterID = fallbackSelection
    }
}

#Preview {
    ContentView()
}

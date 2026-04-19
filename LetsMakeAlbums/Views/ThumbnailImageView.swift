//
//  ThumbnailImageView.swift
//  LetsMakeAlbums
//
//  Created by Dor Luzgarten on 15/04/2026.
//

import Photos
import SwiftUI

struct ThumbnailImageView: View {
    let asset: PHAsset?

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
        .task(id: asset?.localIdentifier) {
            requestThumbnail()
        }
        .onDisappear {
            cancelRequest()
        }
    }

    private func requestThumbnail() {
        cancelRequest()
        image = nil

        guard let asset else { return }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let targetSize = CGSize(width: 150 * scale, height: 150 * scale)
        let requestedID = asset.localIdentifier

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false  // thumbnails are always local; no iCloud pull

        requestID = PhotoImageCache.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            guard let image else { return }
            if (info?[PHImageCancelledKey] as? Bool) == true { return }
            Task { @MainActor in
                guard self.asset?.localIdentifier == requestedID else { return }
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

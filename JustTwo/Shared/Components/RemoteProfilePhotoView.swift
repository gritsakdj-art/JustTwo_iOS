import SwiftUI

struct RemoteProfilePhotoView: View {
    let photo: ProfilePhotoDTO
    var onLoadFailure: (() async -> Void)?

    @State private var reloadToken = 0
    @State private var resolvedURL: URL?
    @State private var didRetry = false

    var body: some View {
        Group {
            if let resolvedURL {
                AsyncImage(url: resolvedURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        failurePlaceholder
                            .task {
                                await handleLoadFailure()
                            }
                    case .empty:
                        ProgressView()
                            .tint(Color.discoverViolet)
                    @unknown default:
                        failurePlaceholder
                    }
                }
                .id("\(photo.id.uuidString)-\(reloadToken)")
            } else {
                failurePlaceholder
            }
        }
        .onAppear {
            resolvedURL = URL(string: photo.downloadUrl)
        }
        .onChange(of: photo.downloadUrl) { _, newValue in
            resolvedURL = URL(string: newValue)
            reloadToken += 1
            didRetry = false
        }
        .onChange(of: photo.id) { _, _ in
            resolvedURL = URL(string: photo.downloadUrl)
            reloadToken += 1
            didRetry = false
        }
    }

    private var failurePlaceholder: some View {
        ZStack {
            Color.discoverMockProfileGradient
            Image(systemName: "photo")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.onAccentText.opacity(0.72))
        }
    }

    private func handleLoadFailure() async {
        guard !didRetry else { return }
        didRetry = true
        await onLoadFailure?()
    }
}

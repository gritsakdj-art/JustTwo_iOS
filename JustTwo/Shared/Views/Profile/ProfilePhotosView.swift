import PhotosUI
import SwiftUI

struct ProfilePhotosView: View {
    @Environment(ProfilePhotoStore.self) private var photoStore

    @State private var selectedItem: PhotosPickerItem?
    @State private var isShowingPhotoPicker = false
    @State private var photoPendingDelete: ProfilePhotoDTO?
    @State private var alertMessage: String?
    @State private var isAlertPresented = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.xl) {
                header
                photoGrid
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
        .localizedNavigationTitle("profile.photos.title")
        .toolbarBackground(.hidden, for: .navigationBar)
        .overlay {
            if photoStore.isLoading && photoStore.photos.isEmpty {
                ProgressView()
                    .tint(Color.discoverViolet)
            }
        }
        .task {
            await photoStore.loadPhotos()
        }
        .photosPicker(isPresented: $isShowingPhotoPicker, selection: $selectedItem, matching: .images)
        .task(id: selectedItem) {
            await handleSelectedPhoto()
        }
        .confirmationDialog(
            Text("profile.photos.delete_confirm_title"),
            isPresented: Binding(
                get: { photoPendingDelete != nil },
                set: { if !$0 { photoPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let photoPendingDelete {
                Button("profile.photos.delete", role: .destructive) {
                    deletePhoto(photoPendingDelete)
                }
            }
            Button("common.cancel", role: .cancel) {
                photoPendingDelete = nil
            }
        } message: {
            Text("profile.photos.delete_confirm_message")
        }
        .alert(Text("common.error.title"), isPresented: $isAlertPresented) {
            Button("common.done", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.brandPrimaryGradient)
                    .frame(width: 76, height: 76)
                    .shadow(color: Color.brandPrimaryGlow.opacity(0.22), radius: 18, x: 0, y: 8)

                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.onAccentText)
            }

            VStack(spacing: 6) {
                Text(photoStore.photos.isEmpty ? "profile.photos.empty_title" : "profile.photos.title")
                    .font(Font.App.manrope(size: 24, weight: .bold))
                    .foregroundStyle(Color.primaryText)
                    .multilineTextAlignment(.center)

                Text("profile.photos.subtitle")
                    .font(Font.App.manrope(size: 15, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
        .padding(.horizontal, AppSpacing.lg)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: AppCornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.card)
                .stroke(Color.hairline, lineWidth: 1)
        )
        .shadow(color: Color.discoverCardShadow.opacity(0.08), radius: 24, x: 0, y: 10)
    }

    private var photoGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(gridItems) { item in
                switch item {
                case .photo(let photo):
                    photoCell(photo)
                case .add:
                    addPhotoCell
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: AppCornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.card)
                .stroke(Color.hairline, lineWidth: 1)
        )
        .shadow(color: Color.discoverCardShadow.opacity(0.06), radius: 20, x: 0, y: 8)
    }

    private var gridItems: [ProfilePhotoGridItem] {
        var items = photoStore.photos.map(ProfilePhotoGridItem.photo)
        if photoStore.canAddPhoto {
            items.append(.add)
        }
        return items
    }

    private func photoCell(_ photo: ProfilePhotoDTO) -> some View {
        ZStack(alignment: .topTrailing) {
            RemoteProfilePhotoView(photo: photo) {
                await photoStore.refreshDownloadURL(for: photo.id)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        photo.isPrimary ? Color.discoverViolet : Color.hairline,
                        lineWidth: photo.isPrimary ? 2 : 1
                    )
            )

            if photo.isPrimary {
                Text("profile.photos.primary_badge")
                    .font(Font.App.manrope(size: 10, weight: .bold))
                    .foregroundStyle(Color.onAccentText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.discoverSelectedGradient, in: Capsule())
                    .padding(8)
            }
        }
        .contextMenu {
            if !photo.isPrimary {
                Button("profile.photos.make_primary") {
                    setPrimary(photo)
                }
            }

            Button("profile.photos.delete", role: .destructive) {
                photoPendingDelete = photo
            }
        }
    }

    private var addPhotoCell: some View {
        Button {
            guard !photoStore.isUploading else { return }
            isShowingPhotoPicker = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                    .fill(Color.fieldBackground)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                            .stroke(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    )

                if photoStore.isUploading {
                    ProgressView()
                        .tint(Color.discoverViolet)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))

                        Text("profile.photos.add")
                            .font(Font.App.manrope(size: 12, weight: .semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.secondaryText)
                    .padding(8)
                }
            }
        }
        .buttonStyle(.spring(pressedScale: 0.96))
        .disabled(photoStore.isUploading || photoStore.isMutating)
        .accessibilityLabel(Text("profile.photos.add"))
    }

    @MainActor
    private func handleSelectedPhoto() async {
        guard let selectedItem else { return }
        defer { self.selectedItem = nil }

        guard let data = try? await selectedItem.loadTransferable(type: Data.self) else {
            presentError(String(localized: "profile.photos.error.invalid_image"))
            return
        }

        do {
            try await photoStore.uploadPhoto(data: data, isPrimary: photoStore.photos.isEmpty)
        } catch let error as LocalizedError {
            presentError(error.errorDescription ?? error.localizedDescription)
        } catch let error as NetworkError {
            presentError(error.userMessage)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func setPrimary(_ photo: ProfilePhotoDTO) {
        Task { @MainActor in
            do {
                try await photoStore.setPrimary(photoID: photo.id)
            } catch let error as NetworkError {
                presentError(error.userMessage)
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    private func deletePhoto(_ photo: ProfilePhotoDTO) {
        photoPendingDelete = nil

        Task { @MainActor in
            do {
                try await photoStore.deletePhoto(photoID: photo.id)
            } catch let error as NetworkError {
                presentError(error.userMessage)
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    private func presentError(_ message: String) {
        alertMessage = message
        isAlertPresented = true
    }
}

private enum ProfilePhotoGridItem: Identifiable {
    case photo(ProfilePhotoDTO)
    case add

    var id: String {
        switch self {
        case .photo(let photo):
            return photo.id.uuidString
        case .add:
            return "add"
        }
    }
}

#Preview {
    NavigationStack {
        ProfilePhotosView()
    }
    .environment(ProfilePhotoStore.shared)
}

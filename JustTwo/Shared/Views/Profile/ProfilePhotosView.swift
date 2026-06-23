import PhotosUI
import SwiftUI
import UIKit

struct ProfilePhotosView: View {
    @Environment(ProfilePhotoStore.self) private var photoStore

    @State private var selectedItem: PhotosPickerItem?
    @State private var isShowingPhotoPicker = false
    @State private var photoPendingDelete: ProfilePhotoDTO?
    @State private var alertMessage: String?
    @State private var isAlertPresented = false

    @State private var liftedPhotoID: UUID?
    @State private var draggedPhotoID: UUID?
    @State private var dragSourceIndex: Int?
    @State private var dragTranslation: CGSize = .zero
    @State private var previewOrder: [UUID]?
    @State private var shouldSetPrimaryOnDrop = false
    @State private var dragSourceFrame: CGRect?
    @State private var primarySlotFrame: CGRect?
    @State private var dragStartCellFrames: [UUID: CGRect] = [:]
    @State private var lastHoverPhotoID: UUID?
    @State private var cellFrames: [UUID: CGRect] = [:]

    private var displayedPhotos: [ProfilePhotoDTO] {
        let photos = photoStore.galleryPhotos
        let order = previewOrder ?? photos.map(\.id)
        return order.compactMap { id in photos.first { $0.id == id } }
    }

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
        .discoverShellBackground()
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
        .onChange(of: photoStore.photos.count) { _, count in
            if count == 0 {
                exitLiftMode(animated: false)
            }
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

                Text(liftedPhotoID != nil ? "profile.photos.edit_hint" : "profile.photos.subtitle")
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
        VStack(spacing: AppSpacing.sm) {
            if liftedPhotoID != nil {
                HStack {
                    Spacer()
                    Button("common.done") {
                        exitLiftMode()
                    }
                    .font(Font.App.manrope(size: 15, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                }
            }

            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: ProfilePhotoGridLayout.columns, spacing: ProfilePhotoGridLayout.spacing) {
                    ForEach(Array(displayedPhotos.enumerated()), id: \.element.id) { index, photo in
                        photoCell(photo, index: index)
                    }

                    if photoStore.canAddPhoto {
                        addPhotoCell
                    }
                }
                .coordinateSpace(name: "profilePhotoGrid")
                .onPreferenceChange(ProfilePhotoCellFramesKey.self) { cellFrames = $0 }

                if let draggedPhotoID,
                   let photo = photoStore.galleryPhotos.first(where: { $0.id == draggedPhotoID }),
                   let frame = dragSourceFrame ?? cellFrames[draggedPhotoID] {
                    dragPreview(photo: photo, sourceFrame: frame)
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

    private func photoCell(_ photo: ProfilePhotoDTO, index: Int) -> some View {
        let isLifted = liftedPhotoID == photo.id
        let isDragging = draggedPhotoID == photo.id
        let isPrimarySlot = index == 0
        let isDropTarget = shouldSetPrimaryOnDrop && isPrimarySlot && draggedPhotoID != nil

        return squarePhotoCell {
            photoImageContent(photo)
        }
        .profilePhotoCellFrame(photoID: photo.id)
        .profilePhotoGridWiggle(isActive: isLifted && !isDragging, seed: wiggleSeed(for: photo.id))
        .scaleEffect(isLifted && !isDragging ? 1.04 : 1)
        .opacity(isDragging ? 0.18 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.photoCell, style: .continuous)
                .stroke(
                    isDropTarget ? Color.discoverViolet : (photo.isPrimary && previewOrder == nil ? Color.discoverViolet : Color.hairline),
                    lineWidth: isDropTarget ? 2.5 : (photo.isPrimary && previewOrder == nil ? 2 : 1)
                )
        }
        .overlay(alignment: .topTrailing) {
            if isLifted {
                deleteBadge(for: photo)
            } else if photo.isPrimary && previewOrder == nil {
                primaryBadge
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.photoCell, style: .continuous))
        .simultaneousGesture(liftedPhotoID == nil ? liftGesture(for: photo) : nil)
        .highPriorityGesture(isLifted ? photoDragGesture(for: photo, index: index) : nil)
        .accessibilityLabel(
            photo.isPrimary
                ? Text("profile.photos.primary_badge")
                : Text("profile.photos.title")
        )
    }

    private func liftGesture(for photo: ProfilePhotoDTO) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in
                liftPhoto(photo)
            }
    }

    private func photoDragGesture(for photo: ProfilePhotoDTO, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("profilePhotoGrid"))
            .onChanged { value in
                guard liftedPhotoID == photo.id, !photoStore.isMutating else { return }

                if draggedPhotoID == nil {
                    draggedPhotoID = photo.id
                    dragSourceIndex = index
                    dragSourceFrame = cellFrames[photo.id]
                    dragStartCellFrames = cellFrames
                    if let primaryID = photoStore.galleryPhotos.first?.id {
                        primarySlotFrame = cellFrames[primaryID]
                    }
                }

                dragTranslation = value.translation

                guard let draggedPhotoID else { return }

                let orderIDs = previewOrder ?? photoStore.galleryPhotos.map(\.id)
                let hoverID = ProfilePhotoGridLayout.photoID(
                    at: value.location,
                    in: dragStartCellFrames,
                    photoIDs: orderIDs
                )

                if let hoverID, hoverID != draggedPhotoID, hoverID != lastHoverPhotoID {
                    swapPreview(draggedID: draggedPhotoID, targetID: hoverID)
                    lastHoverPhotoID = hoverID
                } else if hoverID == nil {
                    lastHoverPhotoID = nil
                }
            }
            .onEnded { value in
                let orderToSave = previewOrder ?? photoStore.galleryPhotos.map(\.id)
                let droppedOnPrimary = primarySlotFrame.map {
                    ProfilePhotoGridLayout.contains(value.location, in: $0)
                } ?? false
                let shouldSetPrimary = shouldSetPrimaryOnDrop && !photo.isPrimary && droppedOnPrimary
                let shouldSaveOrder = previewOrder != nil && previewOrder != photoStore.galleryPhotos.map(\.id)

                defer {
                    draggedPhotoID = nil
                    dragTranslation = .zero
                    dragSourceIndex = nil
                    dragSourceFrame = nil
                    primarySlotFrame = nil
                    dragStartCellFrames = [:]
                    lastHoverPhotoID = nil
                    shouldSetPrimaryOnDrop = false
                    previewOrder = nil
                }

                guard liftedPhotoID == photo.id, !photoStore.isMutating else { return }

                if shouldSetPrimary {
                    setPrimary(photo, displayOrder: orderToSave)
                } else if shouldSaveOrder {
                    reorderPhotos(orderToSave)
                }
            }
    }

    private func dragPreview(photo: ProfilePhotoDTO, sourceFrame: CGRect) -> some View {
        squarePhotoCell {
            photoImageContent(photo)
        }
        .frame(width: sourceFrame.width, height: sourceFrame.height)
        .position(
            x: sourceFrame.midX + dragTranslation.width,
            y: sourceFrame.midY + dragTranslation.height
        )
        .shadow(color: Color.discoverCardShadow.opacity(0.28), radius: 18, x: 0, y: 10)
        .scaleEffect(1.08)
        .allowsHitTesting(false)
        .zIndex(10)
    }

    @ViewBuilder
    private func photoImageContent(_ photo: ProfilePhotoDTO) -> some View {
        if let cached = photoStore.cachedImage(for: photo.id) {
            Image(uiImage: cached)
                .resizable()
                .scaledToFill()
        } else {
            RemoteProfilePhotoView(photo: photo) {
                await photoStore.refreshDownloadURL(for: photo.id)
            }
            .id(photo.id)
        }
    }

    private var primaryBadge: some View {
        Text("profile.photos.primary_badge")
            .font(Font.App.manrope(size: 10, weight: .bold))
            .foregroundStyle(Color.onAccentText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.discoverSelectedGradient, in: Capsule())
            .padding(8)
    }

    private func deleteBadge(for photo: ProfilePhotoDTO) -> some View {
        Button {
            photoPendingDelete = photo
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.onAccentText)
                .frame(width: 24, height: 24)
                .background(Color.primaryText.opacity(0.82), in: Circle())
                .overlay(Circle().stroke(Color.cardSurface, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .offset(x: 8, y: -8)
        .accessibilityLabel(Text("profile.photos.delete"))
    }

    private func squarePhotoCell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.photoCell, style: .continuous))
    }

    private var addPhotoCell: some View {
        Button {
            guard !photoStore.isUploading, liftedPhotoID == nil else { return }
            isShowingPhotoPicker = true
        } label: {
            squarePhotoCell {
                ZStack {
                    RoundedRectangle(cornerRadius: AppCornerRadius.photoCell, style: .continuous)
                        .fill(Color.fieldBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCornerRadius.photoCell, style: .continuous)
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
        }
        .buttonStyle(.spring(pressedScale: 0.96))
        .disabled(photoStore.isUploading || photoStore.isMutating || liftedPhotoID != nil)
        .opacity(liftedPhotoID != nil ? 0.45 : 1)
        .accessibilityLabel(Text("profile.photos.add"))
    }

    private func liftPhoto(_ photo: ProfilePhotoDTO) {
        guard !photoStore.isMutating else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
            liftedPhotoID = photo.id
        }
    }

    private func exitLiftMode(animated: Bool = true) {
        let updates = {
            liftedPhotoID = nil
            draggedPhotoID = nil
            dragSourceIndex = nil
            dragTranslation = .zero
            dragSourceFrame = nil
            primarySlotFrame = nil
            dragStartCellFrames = [:]
            lastHoverPhotoID = nil
            shouldSetPrimaryOnDrop = false
            previewOrder = nil
        }

        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                updates()
            }
        } else {
            updates()
        }
    }

    private func swapPreview(draggedID: UUID, targetID: UUID) {
        var ids = previewOrder ?? photoStore.galleryPhotos.map(\.id)
        guard let from = ids.firstIndex(of: draggedID),
              let to = ids.firstIndex(of: targetID),
              from != to else {
            return
        }

        ids.swapAt(from, to)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            previewOrder = ids
            dragSourceIndex = ids.firstIndex(of: draggedID)
            if to == 0 {
                shouldSetPrimaryOnDrop = true
            }
        }
    }

    private func wiggleSeed(for photoID: UUID) -> Double {
        Double(abs(photoID.hashValue % 100))
    }

    @MainActor
    private func handleSelectedPhoto() async {
        guard let selectedItem else { return }
        defer { self.selectedItem = nil }

        guard let data = try? await selectedItem.loadTransferable(type: Data.self) else {
            presentError(String(localized: "profile.photos.error.invalid_image"))
            return
        }

        if let prepared = ProfilePhotoImagePipeline.prepareJPEG(from: data) {
            do {
                _ = try await photoStore.uploadPreparedPhoto(
                    prepared,
                    isPrimary: photoStore.photos.isEmpty
                )
            } catch let error as LocalizedError {
                presentError(error.errorDescription ?? error.localizedDescription)
            } catch let error as NetworkError {
                presentError(error.userMessage)
            } catch {
                presentError(error.localizedDescription)
            }
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

    private func setPrimary(_ photo: ProfilePhotoDTO, displayOrder: [UUID]) {
        Task { @MainActor in
            do {
                try await photoStore.reorderPhotos(photoIDs: displayOrder)
                try await photoStore.setPrimary(photoID: photo.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                exitLiftMode()
            } catch let error as NetworkError {
                presentError(error.userMessage)
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    private func reorderPhotos(_ photoIDs: [UUID]) {
        Task { @MainActor in
            do {
                try await photoStore.reorderPhotos(photoIDs: photoIDs)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                exitLiftMode()
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
                if liftedPhotoID == photo.id {
                    exitLiftMode(animated: false)
                }
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

#Preview {
    NavigationStack {
        ProfilePhotosView()
    }
    .environment(ProfilePhotoStore.shared)
}

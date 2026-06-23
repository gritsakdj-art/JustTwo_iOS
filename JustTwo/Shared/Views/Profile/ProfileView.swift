import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(ProfilePhotoStore.self) private var photoStore

    @State private var pendingLocalAvatar: UIImage?
    @State private var avatarErrorMessage: String?
    @State private var isAvatarErrorPresented = false
    @State private var isUploadingAvatar = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.xl) {
                        profileSummary
                        menuSection
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xl)
                }

                PrimaryButton(
                    "profile.logout",
                    systemImage: "rectangle.portrait.and.arrow.right"
                ) {
                    session.signOut()
                    router.resetTo(.auth)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.discoverBackgroundGradient.ignoresSafeArea())
            .localizedNavigationTitle("tab.profile")
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await photoStore.loadPhotos()
            }
            .onChange(of: photoStore.primaryPhoto?.id) { _, _ in
                pendingLocalAvatar = nil
            }
            .alert(Text("common.error.title"), isPresented: $isAvatarErrorPresented) {
                Button("common.done", role: .cancel) { }
            } message: {
                Text(avatarErrorMessage ?? "")
            }
        }
    }

    private var profileSummary: some View {
        VStack(spacing: AppSpacing.lg) {
            avatarNavigationLink

            VStack(spacing: 6) {
                Text(session.currentProfile?.displayName ?? String(localized: "profile.current_user.name"))
                    .font(Font.App.manrope(size: 28, weight: .bold))
                    .foregroundStyle(Color.discoverPrimaryText)
                    .multilineTextAlignment(.center)

                Text(session.currentUser?.email ?? String(localized: "profile.current_user.subtitle"))
                    .font(Font.App.manrope(size: 15, weight: .medium))
                    .foregroundStyle(Color.discoverSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
        .padding(.horizontal, AppSpacing.lg)
        .background(Color.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.discoverViolet.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.discoverCardShadow.opacity(0.08), radius: 24, x: 0, y: 10)
    }

    private var avatarNavigationLink: some View {
        NavigationLink {
            AvatarCropEditorView(
                initialImage: pendingLocalAvatar ?? avatarUIImage,
                onSave: { avatarData in
                    uploadAvatar(data: avatarData)
                },
                onDelete: {
                    deleteAvatar()
                }
            )
        } label: {
            avatarView
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("profile.avatar.edit"))
    }

    private var avatarUIImage: UIImage? {
        if let pendingLocalAvatar {
            return pendingLocalAvatar
        }
        return nil
    }

    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(Color.discoverMockProfileGradient)

                if let pendingLocalAvatar {
                    Image(uiImage: pendingLocalAvatar)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 118, height: 118)
                        .clipShape(Circle())
                } else if let primaryPhoto = photoStore.primaryPhoto {
                    RemoteProfilePhotoView(photo: primaryPhoto) {
                        await photoStore.refreshDownloadURL(for: primaryPhoto.id)
                    }
                    .id(primaryPhoto.id)
                    .frame(width: 118, height: 118)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 62, weight: .regular))
                        .foregroundStyle(Color.onAccentText.opacity(0.88))
                }

                if isUploadingAvatar || photoStore.isUploading {
                    Circle()
                        .fill(Color.discoverPrimaryText.opacity(0.28))
                        .frame(width: 118, height: 118)
                    ProgressView()
                        .tint(Color.onAccentText)
                }
            }
            .frame(width: 118, height: 118)
            .overlay(
                Circle()
                    .stroke(Color.onAccentText.opacity(0.65), lineWidth: 3)
            )
            .shadow(color: Color.discoverViolet.opacity(0.22), radius: 22, x: 0, y: 10)

            Image(systemName: "camera.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.onAccentText)
                .frame(width: 34, height: 34)
                .background(Color.brandPrimaryGradient, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.surface.opacity(0.92), lineWidth: 2)
                )
                .shadow(color: Color.brandPrimary.opacity(0.24), radius: 10, x: 0, y: 5)
                .offset(x: -2, y: -2)
        }
        .accessibilityLabel(Text("profile.avatar.placeholder"))
    }

    private var menuSection: some View {
        VStack(spacing: 10) {
            NavigationLink {
                ProfilePhotosView()
            } label: {
                ProfileMenuRowContent(
                    iconName: "photo.stack.fill",
                    title: "profile.menu.my_photos"
                )
            }
            .buttonStyle(ProfileMenuRowStyle())
            .accessibilityLabel(Text("profile.menu.my_photos"))

            NavigationLink {
                GeneralSettingsView()
            } label: {
                ProfileMenuRowContent(
                    iconName: "gearshape.fill",
                    title: "profile.menu.general_settings"
                )
            }
            .buttonStyle(ProfileMenuRowStyle())
            .accessibilityLabel(Text("profile.menu.general_settings"))

            NavigationLink {
                ProfileSettingsView()
            } label: {
                ProfileMenuRowContent(
                    iconName: "person.text.rectangle.fill",
                    title: "profile.menu.profile_settings"
                )
            }
            .buttonStyle(ProfileMenuRowStyle())
            .accessibilityLabel(Text("profile.menu.profile_settings"))
        }
    }

    private func uploadAvatar(data: Data) {
        guard photoStore.canAddPhoto else {
            avatarErrorMessage = String(localized: "profile.photos.error.avatar_limit_reached")
            isAvatarErrorPresented = true
            return
        }

        guard let image = UIImage(data: data) else {
            avatarErrorMessage = String(localized: "profile.photos.error.invalid_image")
            isAvatarErrorPresented = true
            return
        }

        pendingLocalAvatar = image
        isUploadingAvatar = true

        Task { @MainActor in
            do {
                try await photoStore.uploadPhoto(data: data, isPrimary: true)
                pendingLocalAvatar = nil
            } catch let error as NetworkError {
                pendingLocalAvatar = nil
                avatarErrorMessage = error.userMessage
                isAvatarErrorPresented = true
            } catch let error as LocalizedError {
                pendingLocalAvatar = nil
                avatarErrorMessage = error.errorDescription ?? error.localizedDescription
                isAvatarErrorPresented = true
            } catch {
                pendingLocalAvatar = nil
                avatarErrorMessage = error.localizedDescription
                isAvatarErrorPresented = true
            }

            isUploadingAvatar = false
        }
    }

    private func deleteAvatar() {
        guard let primaryPhoto = photoStore.primaryPhoto else {
            pendingLocalAvatar = nil
            return
        }

        Task { @MainActor in
            do {
                try await photoStore.deletePhoto(photoID: primaryPhoto.id)
                pendingLocalAvatar = nil
            } catch let error as NetworkError {
                avatarErrorMessage = error.userMessage
                isAvatarErrorPresented = true
            } catch {
                avatarErrorMessage = error.localizedDescription
                isAvatarErrorPresented = true
            }
        }
    }
}

private struct ProfileMenuRowContent: View {
    let iconName: String
    let title: LocalizedStringResource

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 38, height: 38)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            Text(title)
                .font(Font.App.manrope(size: 16, weight: .semibold))
                .foregroundStyle(Color.discoverPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            Image(systemName: "chevron.forward")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.discoverSecondaryText.opacity(0.72))
        }
        .padding(.horizontal, AppSpacing.sm)
        .frame(height: 62)
        .background(Color.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.discoverViolet.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct ProfileMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .springButtonEffect(
                isPressed: configuration.isPressed,
                pressedScale: 0.98,
                pressedOpacity: 0.86,
                response: 0.2,
                dampingFraction: 0.75
            )
    }
}

#Preview {
    ProfileView()
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
        .environment(ProfilePhotoStore.shared)
}

#Preview("Arabic RTL") {
    ProfileView()
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
        .environment(ProfilePhotoStore.shared)
}

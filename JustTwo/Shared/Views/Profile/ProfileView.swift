import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session

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
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text("tab.profile"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var profileSummary: some View {
        VStack(spacing: AppSpacing.lg) {
            avatarPlaceholder

            VStack(spacing: 6) {
                Text(session.currentProfile?.displayName ?? String(localized: "profile.current_user.name"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.discoverPrimaryText)
                    .multilineTextAlignment(.center)

                Text(session.currentUser?.email ?? String(localized: "profile.current_user.subtitle"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
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

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.discoverMockProfileGradient)

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 62, weight: .regular))
                .foregroundStyle(Color.onAccentText.opacity(0.88))
        }
        .frame(width: 118, height: 118)
        .overlay(
            Circle()
                .stroke(Color.onAccentText.opacity(0.65), lineWidth: 3)
        )
        .shadow(color: Color.discoverViolet.opacity(0.22), radius: 22, x: 0, y: 10)
        .accessibilityLabel(Text("profile.avatar.placeholder"))
    }

    private var menuSection: some View {
        VStack(spacing: 10) {
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
                .font(.system(size: 16, weight: .semibold, design: .rounded))
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
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        ProfileView()
    }
    .environment(SessionStore.shared)
}

#Preview("Arabic RTL") {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        ProfileView()
    }
    .environment(\.locale, Locale(identifier: "ar"))
    .environment(\.layoutDirection, .rightToLeft)
}

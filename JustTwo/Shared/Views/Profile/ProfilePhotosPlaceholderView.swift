import SwiftUI

struct ProfilePhotosPlaceholderView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.xl) {
                header
                photoGridPlaceholder
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
        .navigationTitle(Text("profile.photos.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.brandPrimaryGradient)
                    .frame(width: 76, height: 76)
                    .shadow(color: Color.brandPrimary.opacity(0.22), radius: 18, x: 0, y: 8)

                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.onAccentText)
            }

            VStack(spacing: 6) {
                Text("profile.photos.empty_title")
                    .font(Font.App.manrope(size: 24, weight: .bold))
                    .foregroundStyle(Color.discoverPrimaryText)
                    .multilineTextAlignment(.center)

                Text("profile.photos.empty_subtitle")
                    .font(Font.App.manrope(size: 15, weight: .medium))
                    .foregroundStyle(Color.discoverSecondaryText)
                    .multilineTextAlignment(.center)
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

    private var photoGridPlaceholder: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("profile.photos.subtitle")
                .font(Font.App.manrope(size: 16, weight: .semibold))
                .foregroundStyle(Color.discoverPrimaryText)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    photoSlot(index: index)
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(Color.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.discoverViolet.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.discoverCardShadow.opacity(0.06), radius: 20, x: 0, y: 8)
    }

    private func photoSlot(index: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.surface.opacity(0.62))
                .aspectRatio(0.78, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            Color.discoverViolet.opacity(index == 0 ? 0.28 : 0.14),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                        )
                )

            VStack(spacing: 8) {
                Image(systemName: index == 0 ? "plus" : "photo")
                    .font(.system(size: 20, weight: .semibold))

                Text(index == 0 ? "profile.avatar_editor.choose_photo" : "profile.photos.slot")
                    .font(Font.App.manrope(size: 12, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(Color.discoverSecondaryText)
            .padding(8)
        }
        .accessibilityLabel(Text(index == 0 ? "profile.avatar_editor.choose_photo" : "profile.photos.slot"))
    }
}

#Preview {
    NavigationStack {
        ProfilePhotosPlaceholderView()
    }
}

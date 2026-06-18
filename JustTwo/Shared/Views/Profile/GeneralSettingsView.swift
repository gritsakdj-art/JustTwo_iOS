import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("app.theme") private var selectedThemeRawValue = AppTheme.system.rawValue

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("settings.theme.section")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.discoverSecondaryText)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(AppTheme.allCases.enumerated()), id: \.element) { index, theme in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                                selectedThemeRawValue = theme.rawValue
                            }
                        } label: {
                            ThemeOptionRow(
                                theme: theme,
                                isSelected: selectedTheme == theme
                            )
                        }
                        .buttonStyle(.spring(pressedScale: 0.98, pressedOpacity: 0.88))

                        if index < AppTheme.allCases.count - 1 {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
                .background(Color.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.discoverViolet.opacity(0.10), lineWidth: 1)
                )
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
        .navigationTitle(Text("profile.menu.general_settings"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: selectedThemeRawValue) ?? .system
    }
}

private struct ThemeOptionRow: View {
    let theme: AppTheme
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isSelected ? Color.onAccentText : Color.brandPrimary)
                .frame(width: 38, height: 38)
                .background {
                    iconBackground
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

            Text(theme.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.discoverPrimaryText)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
            }
        }
        .frame(height: 60)
        .padding(.horizontal, AppSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch theme {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    @ViewBuilder
    private var iconBackground: some View {
        if isSelected {
            Color.brandPrimaryGradient
        } else {
            Color.brandPrimary.opacity(0.12)
        }
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}

#Preview("Arabic RTL") {
    NavigationStack {
        GeneralSettingsView()
    }
    .environment(\.locale, Locale(identifier: "ar"))
    .environment(\.layoutDirection, .rightToLeft)
}

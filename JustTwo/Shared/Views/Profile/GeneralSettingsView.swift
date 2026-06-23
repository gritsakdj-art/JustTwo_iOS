import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("app.language") private var selectedLanguageRawValue = AppLanguage.system.rawValue
    @AppStorage("app.theme") private var selectedThemeRawValue = AppTheme.system.rawValue
    @State private var expandedPicker: SettingsPickerKind?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                themePicker
                languagePicker
            }
            .id(selectedLanguageRawValue)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
        .localizedNavigationTitle("profile.menu.general_settings")
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguageRawValue) ?? .system
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: selectedThemeRawValue) ?? .system
    }

    private var themePicker: some View {
        SettingsPickerSection(
            title: "settings.theme.section",
            isExpanded: expandedPicker == .theme,
            selectedRow: {
                SettingsPickerOptionRow(
                    iconName: selectedTheme.iconName,
                    title: Text(selectedTheme.title),
                    isSelected: true,
                    trailingIconName: expandedPicker == .theme ? "chevron.up" : "chevron.down"
                )
            },
            options: {
                ForEach(Array(AppTheme.allCases.enumerated()), id: \.element) { index, theme in
                    Button {
                        selectTheme(theme)
                    } label: {
                        SettingsPickerOptionRow(
                            iconName: theme.iconName,
                            title: Text(theme.title),
                            isSelected: selectedTheme == theme,
                            trailingIconName: selectedTheme == theme ? "checkmark.circle.fill" : nil
                        )
                    }
                    .buttonStyle(.spring(pressedScale: 0.98, pressedOpacity: 0.88))

                    if index < AppTheme.allCases.count - 1 {
                        pickerDivider
                    }
                }
            },
            toggle: {
                togglePicker(.theme)
            }
        )
    }

    private var languagePicker: some View {
        SettingsPickerSection(
            title: "settings.language.section",
            isExpanded: expandedPicker == .language,
            selectedRow: {
                SettingsPickerOptionRow(
                    iconName: selectedLanguage.iconName,
                    title: selectedLanguage.title,
                    subtitle: selectedLanguage.subtitle,
                    isSelected: true,
                    trailingIconName: expandedPicker == .language ? "chevron.up" : "chevron.down"
                )
            },
            options: {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { index, language in
                    Button {
                        selectLanguage(language)
                    } label: {
                        SettingsPickerOptionRow(
                            iconName: language.iconName,
                            title: language.title,
                            subtitle: language.subtitle,
                            isSelected: selectedLanguage == language,
                            trailingIconName: selectedLanguage == language ? "checkmark.circle.fill" : nil
                        )
                    }
                    .buttonStyle(.spring(pressedScale: 0.98, pressedOpacity: 0.88))

                    if index < AppLanguage.allCases.count - 1 {
                        pickerDivider
                    }
                }
            },
            toggle: {
                togglePicker(.language)
            }
        )
    }

    private var pickerDivider: some View {
        Divider()
            .padding(.leading, 58)
            .padding(.trailing, AppSpacing.sm)
    }

    private func togglePicker(_ picker: SettingsPickerKind) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            expandedPicker = expandedPicker == picker ? nil : picker
        }
    }

    private func selectTheme(_ theme: AppTheme) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
            selectedThemeRawValue = theme.rawValue
            expandedPicker = nil
        }
    }

    private func selectLanguage(_ language: AppLanguage) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
            selectedLanguageRawValue = language.rawValue
            expandedPicker = nil
        }
    }
}

private enum SettingsPickerKind {
    case theme
    case language
}

private struct SettingsPickerSection<SelectedRow: View, Options: View>: View {
    let title: LocalizedStringResource
    let isExpanded: Bool
    @ViewBuilder let selectedRow: () -> SelectedRow
    @ViewBuilder let options: () -> Options
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(Font.App.manrope(size: 13, weight: .bold))
                .foregroundStyle(Color.discoverSecondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Button(action: toggle) {
                    selectedRow()
                }
                .buttonStyle(.spring(pressedScale: 0.98, pressedOpacity: 0.9))

                if isExpanded {
                    Divider()
                        .padding(.leading, 58)
                        .padding(.trailing, AppSpacing.sm)

                    VStack(spacing: 0) {
                        options()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(Color.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.discoverViolet.opacity(isExpanded ? 0.22 : 0.10), lineWidth: 1)
            )
            .shadow(color: Color.discoverCardShadow.opacity(isExpanded ? 0.10 : 0.06), radius: 22, x: 0, y: 10)
        }
    }
}

private struct SettingsPickerOptionRow: View {
    let iconName: String
    let title: Text
    var subtitle: String?
    let isSelected: Bool
    var trailingIconName: String?

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isSelected ? Color.onAccentText : Color.brandPrimary)
                .frame(width: 38, height: 38)
                .background {
                    iconBackground
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(Font.App.manrope(size: 16, weight: .semibold))
                    .foregroundStyle(Color.discoverPrimaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(Font.App.caption(size: 12, weight: .medium))
                        .foregroundStyle(Color.discoverSecondaryText)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            if let trailingIconName {
                Image(systemName: trailingIconName)
                    .font(.system(size: trailingIconName.hasPrefix("chevron") ? 13 : 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.discoverSecondaryText.opacity(0.72))
            }
        }
        .frame(minHeight: 60)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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

private extension AppTheme {
    var iconName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
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

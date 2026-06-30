import SwiftUI
import UserNotifications

struct GeneralSettingsView: View {
    @AppStorage("app.language") private var selectedLanguageRawValue = AppLanguage.system.rawValue
    @AppStorage("app.theme") private var selectedThemeRawValue = AppTheme.system.rawValue
    @AppStorage(MessageNotificationPreferences.messagesEnabledKey) private var messagesEnabled = false
    @AppStorage(MessageNotificationPreferences.messagePreviewEnabledKey) private var messagePreviewEnabled = true
    @State private var expandedPicker: SettingsPickerKind?
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequestingPermission = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                themePicker
                languagePicker
                notificationsSection
            }
            .id(selectedLanguageRawValue)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .discoverShellBackground()
        .localizedNavigationTitle("profile.menu.general_settings")
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            authorizationStatus = await MessengerNotificationService.shared.authorizationStatus()
        }
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

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("settings.notifications.section")
                .font(Font.App.manrope(size: 13, weight: .bold))
                .foregroundStyle(Color.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                NotificationSettingsToggleRow(
                    iconName: "bell.badge.fill",
                    title: "settings.notifications.messages.title",
                    subtitle: "settings.notifications.messages.subtitle",
                    isOn: $messagesEnabled,
                    isToggleDisabled: isRequestingPermission
                )
                .onChange(of: messagesEnabled) { _, isEnabled in
                    guard isEnabled else { return }
                    Task {
                        await handleMessagesToggleEnabled()
                    }
                }

                SettingsPickerDivider()

                NotificationSettingsToggleRow(
                    iconName: "text.bubble.fill",
                    title: "settings.notifications.preview.title",
                    subtitle: "settings.notifications.preview.subtitle",
                    isOn: $messagePreviewEnabled,
                    isToggleDisabled: !messagesEnabled || isRequestingPermission
                )
            }
            .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
            .shadow(color: Color.discoverCardShadow.opacity(0.08), radius: 24, x: 0, y: 10)

            if authorizationStatus == .denied {
                Text("settings.notifications.permission_denied")
                    .font(Font.App.footnote())
                    .foregroundStyle(Color.error)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func handleMessagesToggleEnabled() async {
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        let granted = await MessengerNotificationService.shared.requestAuthorization()
        authorizationStatus = await MessengerNotificationService.shared.authorizationStatus()

        if granted {
            let session = SessionStore.shared
            let router = AppRouter.shared
            session.connectRealtimeIfEligible()
            ConversationListViewModel.shared.activateRealtime(session: session, router: router)
        } else {
            messagesEnabled = false
        }
    }

    private var pickerDivider: some View {
        SettingsPickerDivider()
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

private struct NotificationSettingsToggleRow: View {
    let iconName: String
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    @Binding var isOn: Bool
    var isToggleDisabled = false

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Font.App.manrope(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primaryText)

                Text(subtitle)
                    .font(Font.App.caption(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.sm)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.discoverViolet)
                .disabled(isToggleDisabled)
        }
        .frame(minHeight: 60)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var iconBadge: some View {
        Image(systemName: iconName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.onAccentText)
            .frame(width: 38, height: 38)
            .background {
                Color.brandPrimaryGradient
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.glassBorderHighlight.opacity(0.34), lineWidth: 0.6)
            }
            .shadow(color: Color.discoverViolet.opacity(0.18), radius: 8, x: 0, y: 3)
    }
}

private struct SettingsPickerDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .padding(.leading, 58)
            .padding(.trailing, AppSpacing.sm)
    }
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
                .foregroundStyle(Color.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Button(action: toggle) {
                    selectedRow()
                }
                .buttonStyle(.spring(pressedScale: 0.98, pressedOpacity: 0.9))

                if isExpanded {
                    SettingsPickerDivider()

                    VStack(spacing: 0) {
                        options()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
            .shadow(color: Color.discoverCardShadow.opacity(isExpanded ? 0.10 : 0.08), radius: 24, x: 0, y: 10)
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
                    .foregroundStyle(Color.primaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(Font.App.caption(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            if let trailingIconName {
                Image(systemName: trailingIconName)
                    .font(.system(size: trailingIconName.hasPrefix("chevron") ? 13 : 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.disabled)
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
            Color.elevatedSurface
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
    .background(Color.discoverBackgroundGradient.ignoresSafeArea())
}

#Preview("Arabic RTL") {
    NavigationStack {
        GeneralSettingsView()
    }
    .environment(\.locale, Locale(identifier: "ar"))
    .environment(\.layoutDirection, .rightToLeft)
    .background(Color.discoverBackgroundGradient.ignoresSafeArea())
}

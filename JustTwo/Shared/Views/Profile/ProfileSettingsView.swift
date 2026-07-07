import SwiftUI

enum ProfileSettingsContext {
    case onboarding
    case settings
}

struct ProfileSettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let context: ProfileSettingsContext

    @State private var displayName = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var selectedGender: ProfileGender?
    @State private var isGenderPickerExpanded = true
    @State private var bio = ""
    @State private var city = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isBirthDatePickerPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeletePasswordSheetPresented = false
    @State private var deletePassword = ""
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var isVisibleInDiscovery = true
    @State private var isUpdatingDiscoveryVisibility = false
    @State private var discoveryVisibilityErrorMessage: String?
    @FocusState private var isBioFocused: Bool

    private let bioLimit = 180

    init(context: ProfileSettingsContext = .settings) {
        self.context = context
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                if context == .onboarding {
                    onboardingHeader
                }

                formCard

                if let errorMessage {
                    Text(errorMessage)
                        .font(Font.App.footnote())
                        .foregroundStyle(Color.error)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                PrimaryButton(
                    "profile.settings.save",
                    isLoading: isSaving,
                    isDisabled: !canSave
                ) {
                    saveProfile()
                }

                if context == .settings {
                    Divider()
                        .overlay(Color.hairline)
                        .padding(.vertical, 2)

                    dangerZone
                }
            }
            .animation(.easeInOut(duration: 0.22), value: errorMessage)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .discoverShellBackground()
        .hideKeyboardOnTap()
        .localizedNavigationTitle(navigationTitle)
        .navigationBarBackButtonHidden(context == .onboarding)
        .onAppear {
            loadExistingProfile()
        }
        .onChange(of: bio) { _, newValue in
            if newValue.count > bioLimit {
                bio = String(newValue.prefix(bioLimit))
            }
        }
        .sheet(isPresented: $isBirthDatePickerPresented) {
            birthDatePickerSheet
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            Text("profile.account.delete_title"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("profile.account.delete_confirm", role: .destructive) {
                deleteAccountErrorMessage = nil
                deletePassword = ""
                isDeletePasswordSheetPresented = true
            }

            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("profile.account.delete_message")
        }
        .sheet(isPresented: $isDeletePasswordSheetPresented) {
            deleteAccountSheet
                .presentationDetents([.height(390)])
                .presentationDragIndicator(.visible)
        }
    }

    private var navigationTitle: LocalizedStringResource {
        context == .onboarding ? "profile.setup.title" : "profile.menu.profile_settings"
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.chatSenderNameGradient)

            Text("profile.setup.subtitle")
                .font(Font.App.subtitle)
                .foregroundStyle(Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("profile.settings.basic_section")

                BaseTextField(
                    title: "profile.settings.name",
                    text: $displayName,
                    textContentType: .name,
                    autocapitalization: .words,
                    errorMessage: nameValidationMessage
                )

                birthDateSection
                genderSection
            }

            Divider()
                .overlay(Color.hairline)

            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("profile.settings.about_section")
                bioSection

                BaseTextField(
                    title: "profile.settings.city",
                    text: $city,
                    textContentType: .addressCity,
                    autocapitalization: .words
                )
            }

            if context == .settings && session.currentProfile != nil {
                Divider()
                    .overlay(Color.hairline)

                discoveryVisibilitySection
            }
        }
        .padding(AppSpacing.lg)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        }
        .shadow(color: Color.discoverCardShadow.opacity(0.10), radius: 24, x: 0, y: 14)
    }

    private var birthDateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("profile.settings.birth_date")

            Button {
                isBirthDatePickerPresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                        .frame(width: 34, height: 34)
                        .background(Color.elevatedSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(birthDate.formatted(date: .abbreviated, time: .omitted))
                            .font(Font.App.manrope(size: 16, weight: .semibold))
                            .foregroundStyle(Color.primaryText)

                        Text(ageDescription)
                            .font(Font.App.caption())
                            .foregroundStyle(Color.secondaryText)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                        .strokeBorder(birthDateValidationMessage == nil ? Color.hairline : Color.error, lineWidth: 1)
                }
            }
            .buttonStyle(.spring(pressedScale: 0.98))

            Text("profile.settings.birth_date.helper")
                .font(Font.App.caption())
                .foregroundStyle(Color.secondaryText)

            if let birthDateValidationMessage {
                Text(birthDateValidationMessage)
                    .font(Font.App.footnote())
                    .foregroundStyle(Color.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: birthDateValidationMessage)
    }

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("profile.settings.gender")

            if let selectedGender, !isGenderPickerExpanded {
                selectedGenderRow(selectedGender)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                LazyVGrid(columns: genderColumns, spacing: 10) {
                    ForEach(ProfileGender.allCases) { gender in
                        let isSelected = selectedGender == gender

                        Button {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                                selectedGender = gender
                                isGenderPickerExpanded = false
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Text(gender.title)
                                    .font(Font.App.manrope(size: 14, weight: isSelected ? .bold : .semibold))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.82)
                                    .multilineTextAlignment(.center)

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                }
                            }
                            .foregroundStyle(isSelected ? Color.onAccentText : Color.discoverViolet)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 46)
                            .padding(.horizontal, 10)
                            .background {
                                if isSelected {
                                    Color.discoverSelectedGradient
                                } else {
                                    Color.fieldBackground
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isSelected ? Color.clear : Color.hairline, lineWidth: 1)
                            }
                            .shadow(color: isSelected ? Color.discoverViolet.opacity(0.20) : Color.clear, radius: 12, x: 0, y: 6)
                        }
                        .buttonStyle(.spring(pressedScale: 0.96))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func selectedGenderRow(_ gender: ProfileGender) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.onAccentText)
                .frame(width: 34, height: 34)
                .background(Color.discoverSelectedGradient, in: Circle())

            Text(gender.title)
                .font(Font.App.manrope(size: 16, weight: .semibold))
                .foregroundStyle(Color.primaryText)

            Spacer(minLength: 12)

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                    isGenderPickerExpanded = true
                }
            } label: {
                Text("profile.settings.gender.edit")
                    .font(Font.App.footnote(weight: .bold))
                    .foregroundStyle(Color.brandPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.elevatedSurface, in: Capsule())
            }
            .buttonStyle(.spring(pressedScale: 0.94))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
    }

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("profile.settings.bio")

            ZStack(alignment: .topLeading) {
                TextEditor(text: $bio)
                    .font(Font.App.manrope(size: 16, weight: .medium))
                    .foregroundStyle(Color.primaryText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 112, maxHeight: 112)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .focused($isBioFocused)

                if bio.isEmpty {
                    Text("profile.settings.bio_placeholder")
                        .font(Font.App.manrope(size: 16, weight: .medium))
                        .foregroundStyle(Color.secondaryText.opacity(0.72))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                    .strokeBorder(isBioFocused ? Color.discoverViolet.opacity(0.55) : Color.hairline, lineWidth: isBioFocused ? 1.5 : 1)
            }
            .animation(.easeOut(duration: 0.18), value: isBioFocused)

            Text(bioCounterText)
                .font(Font.App.caption())
                .foregroundStyle(bioCounterColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .animation(.easeOut(duration: 0.15), value: bio.count)
        }
    }

    private var discoveryVisibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("profile.settings.privacy_section")

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: isVisibleInDiscovery ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.onAccentText)
                        .frame(width: 36, height: 36)
                        .background(Color.discoverSelectedGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentTransition(.symbolEffect(.replace))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("profile.settings.discovery_visibility.title")
                            .font(Font.App.manrope(size: 16, weight: .bold))
                            .foregroundStyle(Color.primaryText)

                        Text("profile.settings.discovery_visibility.subtitle")
                            .font(Font.App.caption())
                            .foregroundStyle(Color.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    if isUpdatingDiscoveryVisibility {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.discoverViolet)
                    }

                    Toggle("profile.settings.discovery_visibility.title", isOn: discoveryVisibilityBinding)
                        .labelsHidden()
                        .tint(Color.discoverViolet)
                        .disabled(isUpdatingDiscoveryVisibility || isSaving)
                }

                if let discoveryVisibilityErrorMessage {
                    Text(discoveryVisibilityErrorMessage)
                        .font(Font.App.footnote())
                        .foregroundStyle(Color.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            }
            .animation(.easeInOut(duration: 0.2), value: isVisibleInDiscovery)
        }
    }

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("profile.account.danger_section")

            Button {
                isDeleteConfirmationPresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.error)
                        .frame(width: 36, height: 36)
                        .background(Color.elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("profile.account.delete")
                            .font(Font.App.manrope(size: 16, weight: .bold))
                            .foregroundStyle(Color.error)

                        Text("profile.account.delete_message")
                            .font(Font.App.caption())
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.secondaryText.opacity(0.72))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.error.opacity(0.08), in: RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                        .stroke(Color.error.opacity(0.22), lineWidth: 1)
                }
            }
            .buttonStyle(.spring(pressedScale: 0.98))
        }
    }

    private var birthDatePickerSheet: some View {
        VStack(spacing: AppSpacing.lg) {
            Text("profile.settings.birth_date.sheet_title")
                .font(Font.App.manrope(size: 17, weight: .bold))
                .foregroundStyle(Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            DatePicker(
                "",
                selection: $birthDate,
                in: earliestBirthDate...latestAllowedBirthDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()

            PrimaryButton("common.done") {
                isBirthDatePickerPresented = false
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
    }

    private var deleteAccountSheet: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("profile.account.delete_password_title")
                    .font(Font.App.manrope(size: 20, weight: .bold))
                    .foregroundStyle(Color.primaryText)

                Text("profile.account.delete_password_subtitle")
                    .font(Font.App.subheadline())
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BaseTextField(
                title: "profile.account.current_password",
                text: $deletePassword,
                isSecure: true,
                textContentType: .password,
                errorMessage: deleteAccountErrorMessage
            )

            destructiveDeleteButton

            Button {
                isDeletePasswordSheetPresented = false
                deletePassword = ""
                deleteAccountErrorMessage = nil
            } label: {
                Text("common.cancel")
                    .font(Font.App.footnote(weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.spring(pressedScale: 0.96))
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
        .interactiveDismissDisabled(isDeletingAccount)
    }

    private var destructiveDeleteButton: some View {
        Button {
            deleteAccount()
        } label: {
            HStack(spacing: 10) {
                if isDeletingAccount {
                    ProgressView()
                        .tint(Color.error)
                } else {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .semibold))
                }

                Text("profile.account.delete")
                    .font(Font.App.manrope(size: 16, weight: .bold))
            }
            .foregroundStyle(Color.error)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.error.opacity(0.08), in: RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                    .stroke(Color.error.opacity(0.22), lineWidth: 1)
            }
            .opacity(deletePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.65 : 1)
        }
        .buttonStyle(.spring(pressedScale: 0.98))
        .disabled(deletePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDeletingAccount)
    }

    private var genderColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 132), spacing: 10)]
    }

    private var canSave: Bool {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.count >= 2 && trimmedName.count <= 40 && isAdult && selectedGender != nil
    }

    private var nameValidationMessage: String? {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return trimmedName.count >= 2 && trimmedName.count <= 40 ? nil : String(localized: "profile.settings.name_error")
    }

    private var birthDateValidationMessage: String? {
        isAdult ? nil : String(localized: "profile.settings.invalid_age")
    }

    private var earliestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date()
    }

    private var latestAllowedBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }

    private var isAdult: Bool {
        birthDate <= latestAllowedBirthDate
    }

    private var ageDescription: String {
        let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        return String.localizedStringWithFormat(String(localized: "profile.settings.age_value"), max(age, 0))
    }

    private var bioCounterText: String {
        String.localizedStringWithFormat(
            String(localized: "profile.settings.bio_counter"),
            bio.count,
            bioLimit
        )
    }

    private var bioCounterColor: Color {
        if bio.count >= bioLimit {
            return .error
        }
        let ratio = Double(bio.count) / Double(bioLimit)
        return ratio > 0.9 ? .warning : .secondaryText
    }

    private var discoveryVisibilityBinding: Binding<Bool> {
        Binding(
            get: { isVisibleInDiscovery },
            set: { newValue in
                updateDiscoveryVisibility(to: newValue)
            }
        )
    }

    private func sectionTitle(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(Font.App.manrope(size: 13, weight: .bold))
            .foregroundStyle(Color.secondaryText)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }

    private func fieldLabel(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(Font.App.manrope(size: 13, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
    }

    private func loadExistingProfile() {
        guard let profile = session.currentProfile else { return }

        displayName = profile.displayName
        bio = profile.bio ?? ""
        city = profile.city ?? ""
        isVisibleInDiscovery = profile.isVisibleInDiscovery

        if let parsedBirthDate = DateOnlyFormatter.date(from: profile.birthDate) {
            birthDate = parsedBirthDate
        }

        if let gender = ProfileGender(rawValue: profile.gender) {
            selectedGender = gender
            isGenderPickerExpanded = false
        }
    }

    private func saveProfile() {
        guard canSave, !isSaving, let selectedGender else { return }

        guard session.isFullyAuthenticated else {
            if let email = session.pendingVerificationEmail ?? session.currentUser?.email {
                router.showCheckEmail(email: email)
            } else {
                router.resetTo(.auth)
            }
            return
        }

        isSaving = true
        errorMessage = nil

        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)

        let body = UpsertProfileRequestBody(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            birthDate: DateOnlyFormatter.string(from: birthDate),
            gender: selectedGender.rawValue,
            bio: trimmedBio.isEmpty ? nil : trimmedBio,
            city: trimmedCity.isEmpty ? nil : trimmedCity,
            latitude: nil,
            longitude: nil,
            moodModeEnabled: true,
            activityModeEnabled: true,
            isVisibleInDiscovery: isVisibleInDiscovery
        )

        Task {
            do {
                let profile = try await ProfileService.upsertProfile(body)
                session.updateCurrentProfile(profile)

                switch context {
                case .onboarding:
                    session.connectRealtimeIfEligible()
                    await AppStartupCoordinator.shared.runCriticalWarmup(
                        session: session,
                        router: router,
                        force: true
                    )
                    router.resetTo(.main)
                    router.presentPendingInviteIfNeeded()
                case .settings:
                    dismiss()
                }
            } catch let error as NetworkError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    private func updateDiscoveryVisibility(to newValue: Bool) {
        guard newValue != isVisibleInDiscovery else { return }
        guard context == .settings, session.currentProfile != nil, !isUpdatingDiscoveryVisibility else { return }

        let previousValue = isVisibleInDiscovery
        isVisibleInDiscovery = newValue
        isUpdatingDiscoveryVisibility = true
        discoveryVisibilityErrorMessage = nil

        let body = UpsertProfileRequestBody(isVisibleInDiscovery: newValue)

        Task {
            do {
                let profile = try await ProfileService.upsertProfile(body)
                session.updateCurrentProfile(profile)
                isVisibleInDiscovery = profile.isVisibleInDiscovery
            } catch let error as NetworkError {
                isVisibleInDiscovery = previousValue
                discoveryVisibilityErrorMessage = error.userMessage
            } catch {
                isVisibleInDiscovery = previousValue
                discoveryVisibilityErrorMessage = error.localizedDescription
            }

            isUpdatingDiscoveryVisibility = false
        }
    }

    private func deleteAccount() {
        let password = deletePassword
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isDeletingAccount else { return }

        isDeletingAccount = true
        deleteAccountErrorMessage = nil

        Task {
            do {
                _ = try await AuthService.deleteAccount(password: password)
                deletePassword = ""
                session.clearSession()
                router.resetTo(.auth)
            } catch let error as NetworkError {
                deletePassword = ""

                if error.shouldClearSession {
                    session.clearSession()
                    router.resetTo(.auth)
                } else if error.isInvalidPassword {
                    deleteAccountErrorMessage = String(localized: "profile.account.error.incorrect_password")
                } else {
                    deleteAccountErrorMessage = error.userMessage
                }
            } catch {
                deletePassword = ""
                deleteAccountErrorMessage = error.localizedDescription
            }

            isDeletingAccount = false
        }
    }
}

#Preview("Onboarding") {
    NavigationStack {
        ProfileSettingsView(context: .onboarding)
    }
    .environment(SessionStore.shared)
    .environment(AppRouter.shared)
}

#Preview("Settings") {
    NavigationStack {
        ProfileSettingsView(context: .settings)
    }
    .environment(SessionStore.shared)
    .environment(AppRouter.shared)
}

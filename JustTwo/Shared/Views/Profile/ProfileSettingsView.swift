import SwiftUI

enum ProfileSettingsContext {
    case onboarding
    case settings
}

struct ProfileSettingsView: View {
    @Environment(SessionStore.self) private var session
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
                        .font(.footnote)
                        .foregroundStyle(Color.discoverPink)
                }

                PrimaryButton(
                    "profile.settings.save",
                    isLoading: isSaving,
                    isDisabled: !canSave
                ) {
                    saveProfile()
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
        .hideKeyboardOnTap()
        .navigationTitle(Text(navigationTitle))
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private var navigationTitle: LocalizedStringResource {
        context == .onboarding ? "profile.setup.title" : "profile.menu.profile_settings"
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("profile.setup.subtitle")
                .font(Font.App.subtitle)
                .foregroundStyle(Color.discoverSecondaryText)
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
                .overlay(Color.discoverViolet.opacity(0.12))

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
        }
        .padding(AppSpacing.lg)
        .background(Color.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.discoverViolet.opacity(0.12), lineWidth: 1)
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
                        .foregroundStyle(Color.discoverViolet)
                        .frame(width: 34, height: 34)
                        .background(Color.discoverViolet.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(birthDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.discoverPrimaryText)

                        Text(ageDescription)
                            .font(.caption)
                            .foregroundStyle(Color.discoverSecondaryText)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.discoverSecondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(birthDateValidationMessage == nil ? Color.discoverSecondaryText.opacity(0.22) : Color.discoverPink, lineWidth: 1)
                }
            }
            .buttonStyle(.spring(pressedScale: 0.98))

            Text("profile.settings.birth_date.helper")
                .font(.caption)
                .foregroundStyle(Color.discoverSecondaryText)

            if let birthDateValidationMessage {
                Text(birthDateValidationMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.discoverPink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                                    .font(.system(size: 14, weight: isSelected ? .bold : .semibold, design: .rounded))
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
                                    Color.surface.opacity(0.82)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.discoverViolet.opacity(isSelected ? 0 : 0.18), lineWidth: 1)
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
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.discoverPrimaryText)

            Spacer(minLength: 12)

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                    isGenderPickerExpanded = true
                }
            } label: {
                Text("profile.settings.gender.edit")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.brandPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.brandPrimary.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.spring(pressedScale: 0.94))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.discoverSecondaryText.opacity(0.22), lineWidth: 1)
        }
    }

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("profile.settings.bio")

            ZStack(alignment: .topLeading) {
                TextEditor(text: $bio)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.discoverPrimaryText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 112, maxHeight: 112)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                if bio.isEmpty {
                    Text("profile.settings.bio_placeholder")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.discoverSecondaryText.opacity(0.72))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.discoverSecondaryText.opacity(0.22), lineWidth: 1)
            }

            Text("\(bio.count)/\(bioLimit)")
                .font(.caption)
                .foregroundStyle(Color.discoverSecondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var birthDatePickerSheet: some View {
        VStack(spacing: AppSpacing.lg) {
            Text("profile.settings.birth_date.sheet_title")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.discoverPrimaryText)
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

    private func sectionTitle(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.discoverSecondaryText)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }

    private func fieldLabel(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.discoverSecondaryText)
    }

    private func loadExistingProfile() {
        guard let profile = session.currentProfile else { return }

        displayName = profile.displayName
        bio = profile.bio ?? ""
        city = profile.city ?? ""

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
            activityModeEnabled: true
        )

        Task {
            do {
                let profile = try await ProfileService.upsertProfile(body)

                switch context {
                case .onboarding, .settings:
                    session.updateCurrentProfile(profile)
                }

                if context == .settings {
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
}

#Preview("Onboarding") {
    NavigationStack {
        ProfileSettingsView(context: .onboarding)
    }
    .environment(SessionStore.shared)
}

#Preview("Settings") {
    NavigationStack {
        ProfileSettingsView(context: .settings)
    }
    .environment(SessionStore.shared)
}

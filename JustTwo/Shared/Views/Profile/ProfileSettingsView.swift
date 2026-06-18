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
    @State private var selectedGender = ProfileGender.woman
    @State private var bio = ""
    @State private var city = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(context: ProfileSettingsContext = .settings) {
        self.context = context
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                if context == .onboarding {
                    onboardingHeader
                }

                VStack(spacing: 16) {
                    BaseTextField(
                        title: "profile.settings.name",
                        text: $displayName,
                        textContentType: .name,
                        autocapitalization: .words
                    )

                    birthDateSection
                    genderSection

                    BaseTextField(
                        title: "profile.settings.bio",
                        text: $bio,
                        autocapitalization: .sentences
                    )

                    BaseTextField(
                        title: "profile.settings.city",
                        text: $city,
                        textContentType: .addressCity,
                        autocapitalization: .words
                    )
                }

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

    private var birthDateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("profile.settings.birth_date")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.discoverSecondaryText)

            DatePicker(
                "",
                selection: $birthDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.discoverSecondaryText.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("profile.settings.gender")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.discoverSecondaryText)

            Picker("profile.settings.gender", selection: $selectedGender) {
                ForEach(ProfileGender.allCases) { gender in
                    Text(gender.title).tag(gender)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.discoverSecondaryText.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private var canSave: Bool {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.count >= 2 && trimmedName.count <= 40
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
        }
    }

    private func saveProfile() {
        guard canSave, !isSaving else { return }

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

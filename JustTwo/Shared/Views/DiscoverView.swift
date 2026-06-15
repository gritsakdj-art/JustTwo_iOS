import SwiftUI

// MARK: - Models

struct Profile {
    let name: String
    let age: Int
    let distanceKm: Double
    let moodTag: String
    let bio: String
    let matchPercent: Int
    let imageName: String // asset name or SF symbol fallback
}

extension Profile {
    static let mockEmma = Profile(
        name: "Emma",
        age: 27,
        distanceKm: 2.4,
        moodTag: "Open to coffee",
        bio: "Slow walks, deep talks, spontaneous plans.",
        matchPercent: 94,
        imageName: "emma_profile"
    )

    static let mockMaya = Profile(
        name: "Maya",
        age: 29,
        distanceKm: 1.8,
        moodTag: "Gallery walk",
        bio: "Modern art, matcha, and finding tiny streets with warm lights.",
        matchPercent: 88,
        imageName: ""
    )
}

enum DiscoverMode: String, CaseIterable {
    case vibe = "Vibe"
    case activity = "Activity"
}

// MARK: - Discover Screen

struct DiscoverView: View {

    @State private var selectedMode: DiscoverMode = .vibe
    @State private var selectedMood: String = "Coffee"
    @State private var selectedTab: AppTab = .discover
    @State private var cardOffset: CGSize = .zero
    @State private var cardRotation: Double = 0
    @State private var isLiked: Bool = false
    @State private var isPassed: Bool = false

    let moods = ["Talk", "Flirt", "Coffee", "Walk", "Movie", "Bar"]

    let profile: Profile
    let usesRemotePhoto: Bool

    init(
        profile: Profile = .mockEmma,
        usesRemotePhoto: Bool = true,
        selectedMode: DiscoverMode = .vibe,
        selectedMood: String = "Coffee"
    ) {
        self.profile = profile
        self.usesRemotePhoto = usesRemotePhoto
        _selectedMode = State(initialValue: selectedMode)
        _selectedMood = State(initialValue: selectedMood)
    }

    var body: some View {
        ZStack {
            Color.discoverBackgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                tabContent
                AppTabBar(selection: $selectedTab)
            }
        }
        .statusBarHidden(false)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .discover:
            discoverContent
        case .matches:
            MatchesView()
        case .chats:
            ChatsView()
        case .plans:
            PlansView()
        case .profile:
            ProfileView()
        }
    }

    private var discoverContent: some View {
        VStack(spacing: 0) {
            segmentedControl
            moodChips
            profileCard
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            actionButtons
                .padding(.bottom, 8)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Header

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("JustTwo")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.discoverPrimaryText)
                    .tracking(-0.8)

                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.discoverViolet)
                    Text("Amsterdam")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.discoverSecondaryText)
                }
            }
            Spacer()
            notificationButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var notificationButton: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.discoverViolet)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.discoverViolet.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.discoverViolet.opacity(0.10), radius: 12, x: 0, y: 2)

            Circle()
                .fill(Color.discoverPink)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.onAccentText, lineWidth: 1.5))
                .offset(x: -4, y: 4)
        }
    }

    // MARK: Segmented Control

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(DiscoverMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                        selectedMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: selectedMode == mode ? .bold : .medium))
                        .foregroundStyle(selectedMode == mode ? Color.onAccentText : Color.discoverSecondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if selectedMode == mode {
                                Color.discoverSelectedGradient
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: Color.discoverViolet.opacity(0.32), radius: 14, x: 0, y: 4)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.discoverViolet.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: Mood Chips

    private var moodChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moods, id: \.self) { mood in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            selectedMood = mood
                        }
                    } label: {
                        Text(mood)
                            .font(.system(size: 13, weight: selectedMood == mood ? .bold : .medium))
                            .foregroundStyle(selectedMood == mood ? Color.onAccentText : Color.discoverViolet)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background {
                                if selectedMood == mood {
                                    Color.discoverMoodGradient
                                    .clipShape(Capsule())
                                    .shadow(color: Color.discoverPink.opacity(0.30), radius: 14, x: 0, y: 4)
                                } else {
                                    Capsule()
                                        .fill(Color.surface.opacity(0.75))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.discoverViolet.opacity(0.20), lineWidth: 1.5)
                                        )
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 18)
    }

    // MARK: Profile Card

    private var profileCard: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                profilePhoto
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                Color.discoverCardOverlayGradient

                Color.discoverCardTopVignette
                .frame(height: 80)
                .frame(maxHeight: .infinity, alignment: .top)

                // Mood pill top-right
                VStack {
                    HStack {
                        Spacer()
                        moodPill
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                    Spacer()
                }

                // Card info
                cardInfo
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .shadow(color: Color.discoverCardShadow.opacity(0.16), radius: 60, x: 0, y: 20)
            .shadow(color: Color.discoverPink.opacity(0.10), radius: 16, x: 0, y: 4)
            .offset(cardOffset)
            .rotationEffect(.degrees(cardRotation))
            .gesture(swipeGesture)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: cardOffset)
        }
    }

    @ViewBuilder
    private var profilePhoto: some View {
        if !profile.imageName.isEmpty {
            Image(profile.imageName)
                .resizable()
                .scaledToFill()
        } else if usesRemotePhoto {
            AsyncImage(
                url: URL(string: "https://images.unsplash.com/photo-1762344352930-1e459b3e8c88?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&w=600&h=780")
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    mockProfileArtwork
                }
            }
        } else {
            mockProfileArtwork
        }
    }

    private var mockProfileArtwork: some View {
        ZStack {
            Color.discoverMockProfileGradient

            VStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 112, weight: .regular))
                    .foregroundStyle(Color.onAccentText.opacity(0.82))

                Text(String(profile.name.prefix(1)))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.onAccentText.opacity(0.72))
                    .frame(width: 86, height: 86)
                    .background(Color.onAccentText.opacity(0.16), in: Circle())
                    .overlay(Circle().stroke(Color.onAccentText.opacity(0.25), lineWidth: 1))
            }
            .offset(y: -44)
        }
    }

    private var moodPill: some View {
        Text(profile.moodTag.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.onAccentText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.onAccentText.opacity(0.28), lineWidth: 1))
            .tracking(0.6)
    }

    private var cardInfo: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(profile.name), \(profile.age)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.onAccentText)
                    .tracking(-0.6)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.discoverOnline)
                        .frame(width: 7, height: 7)
                        .shadow(color: Color.discoverOnline, radius: 4)
                    Text(String(format: "%.1f km away", profile.distanceKm))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.onAccentText.opacity(0.75))
                }

                Text(profile.bio)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.onAccentText.opacity(0.68))
                    .lineLimit(2)
                    .frame(maxWidth: 220, alignment: .leading)
            }
            Spacer()
            matchRing
        }
    }

    private var matchRing: some View {
        ZStack {
            Circle()
                .fill(
                    Color.discoverSelectedGradient
                )
                .frame(width: 52, height: 52)
            Circle()
                .fill(Color.discoverPrimaryText.opacity(0.75))
                .frame(width: 46, height: 46)
            Text("\(profile.matchPercent)%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.onAccentText)
                .tracking(-0.4)
        }
        .shadow(color: Color.discoverViolet.opacity(0.4), radius: 16, x: 0, y: 4)
    }

    // MARK: Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                cardOffset = value.translation
                cardRotation = Double(value.translation.width / 20)
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                if value.translation.width > threshold {
                    withAnimation(.spring()) {
                        isLiked = true
                        cardOffset = CGSize(width: 600, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        resetCard()
                    }
                } else if value.translation.width < -threshold {
                    withAnimation(.spring()) {
                        isPassed = true
                        cardOffset = CGSize(width: -600, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        resetCard()
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        cardOffset = .zero
                        cardRotation = 0
                    }
                }
            }
    }

    private func resetCard() {
        cardOffset = .zero
        cardRotation = 0
        isLiked = false
        isPassed = false
    }

    // MARK: Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 20) {
            // Pass
            ActionButton(
                icon: "xmark",
                size: 60,
                iconSize: 22,
                style: .outlined(
                    iconColor: Color.discoverPink,
                    borderColor: Color.discoverPink.opacity(0.25)
                )
            ) {
                withAnimation(.spring()) {
                    cardOffset = CGSize(width: -600, height: 0)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { resetCard() }
            }

            // Like
            ActionButton(
                icon: "heart.fill",
                size: 72,
                iconSize: 26,
                style: .gradient(
                    gradient: isLiked
                        ? Color.discoverMoodGradient
                        : Color.discoverSelectedGradient,
                    shadowColor: isLiked
                        ? Color.discoverPink.opacity(0.42)
                        : Color.discoverViolet.opacity(0.38)
                )
            ) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    isLiked.toggle()
                }
            }

            // Invite
            ActionButton(
                icon: "paperplane",
                size: 60,
                iconSize: 20,
                style: .outlined(
                    iconColor: Color.discoverViolet,
                    borderColor: Color.discoverViolet.opacity(0.20)
                )
            ) { }
        }
        .padding(.horizontal, 24)
    }

}

// MARK: - Action Button

enum ActionButtonStyle {
    case gradient(gradient: LinearGradient, shadowColor: Color)
    case outlined(iconColor: Color, borderColor: Color)
}

struct ActionButton: View {
    let icon: String
    let size: CGFloat
    let iconSize: CGFloat
    let style: ActionButtonStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(iconForeground)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(Circle())
                .shadow(color: shadowColor, radius: 16, x: 0, y: 8)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .gradient(let gradient, _):
            gradient
        case .outlined(_, let borderColor):
            ZStack {
                Color.surface.opacity(0.85)
                Circle().stroke(borderColor, lineWidth: 1.5)
            }
        }
    }

    private var iconForeground: Color {
        switch style {
        case .gradient: return Color.onAccentText
        case .outlined(let iconColor, _): return iconColor
        }
    }

    private var shadowColor: Color {
        switch style {
        case .gradient(_, let shadowColor): return shadowColor
        case .outlined: return Color.discoverViolet.opacity(0.10)
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview("Discover - Vibe") {
    DiscoverView(profile: .mockEmma, usesRemotePhoto: false)
}

#Preview("Discover - Activity") {
    DiscoverView(
        profile: .mockMaya,
        usesRemotePhoto: false,
        selectedMode: .activity,
        selectedMood: "Walk"
    )
}

#Preview("Discover - Dark") {
    DiscoverView(
        profile: .mockMaya,
        usesRemotePhoto: false,
        selectedMode: .activity,
        selectedMood: "Movie"
    )
        .preferredColorScheme(.dark)
}

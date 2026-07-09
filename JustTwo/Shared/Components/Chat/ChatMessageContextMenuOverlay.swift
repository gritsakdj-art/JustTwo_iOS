import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ChatMessageContextMenuOverlay: View {
    let message: ChatMessage
    let anchor: CGRect
    /// Эмодзи текущей реакции пользователя на это сообщение (если есть).
    /// Прокинь сюда, например, `message.reactions.first(where: { $0.reactedByMe })?.emoji`.
    var currentReactionEmoji: String? = nil
    let onReply: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReact: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var areReactionsExpanded = false

    // MARK: - Magnify gesture state (Пункт 3)

    @State private var reactionFrames: [String: CGRect] = [:]
    @State private var dragLocation: CGPoint? = nil
    @State private var activeMagnifiedID: String? = nil

    private var reactionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Metrics.reactionsGridSpacing), count: 6)
    }

    private var resolvedCurrentReactionEmoji: String? {
        if let currentReactionEmoji {
            return ReactionEmoji.normalized(currentReactionEmoji)
        }
        return message.reactions.first(where: { $0.reactedByMe }).map {
            ReactionEmoji.normalized($0.emoji)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                dimmingBackground
                    .onTapGesture(perform: onDismiss)

                centeredContextMenu(in: geometry)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(.all, edges: .all)
        .onAppear {
            areReactionsExpanded = false
        }
        .transition(.opacity)
    }

    // MARK: - Background

    private var dimmingBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Rectangle()
                .fill(colorScheme == .dark
                    ? Color.black.opacity(Metrics.dimmingTintDark)
                    : Color.black.opacity(Metrics.dimmingTintLight))
        }
        .ignoresSafeArea(.all, edges: .all)
    }

    private func centeredContextMenu(in geometry: GeometryProxy) -> some View {
        let bubbleMaxWidth = min(
            geometry.size.width - Metrics.centerHorizontalPadding * 2,
            Metrics.previewBubbleMaxWidth
        )
        let topInset = geometry.safeAreaInsets.top + Metrics.centerVerticalPadding
        let bottomInset = geometry.safeAreaInsets.bottom + Metrics.centerVerticalPadding
        let visibleHeight = max(0, geometry.size.height - topInset - bottomInset)

        return ScrollView(.vertical, showsIndicators: false) {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: Metrics.panelGap) {
                    if message.canReact {
                        reactionsPanel
                            .frame(width: Metrics.panelWidth)
                    }

                    messagePreviewBubble(maxWidth: bubbleMaxWidth)

                    actionsPanel
                        .frame(width: Metrics.panelWidth)
                }
            }
            .padding(.horizontal, Metrics.centerHorizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(minHeight: visibleHeight, alignment: .center)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    private func messagePreviewBubble(maxWidth: CGFloat) -> some View {
        ChatBubbleView(
            text: message.displayText,
            senderName: nil,
            createdAt: message.createdAt,
            isMine: message.isMine,
            replyPreview: message.replyPreview?.isDeleted == false ? message.replyPreview?.body : nil,
            replyImageAttachment: nil,
            onReplyTap: nil,
            imageAttachment: message.imageAttachment,
            isEdited: message.isEdited,
            isDeleted: message.isDeleted,
            reactions: message.reactions,
            deliveryStatus: message.deliveryStatus,
            localSendState: message.localSendState,
            onRetry: nil,
            onReactionTap: nil,
            onImageTap: nil
        )
        .frame(maxWidth: maxWidth, alignment: .center)
        .allowsHitTesting(false)
    }

    // MARK: - Panels

    private var reactionsPanel: some View {
        VStack(alignment: .leading, spacing: Metrics.reactionsVStackSpacing) {
            if areReactionsExpanded {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Metrics.reactionsVStackSpacing) {
                        ForEach(Array(ChatQuickReactions.rows.enumerated()), id: \.offset) { rowIndex, row in
                            reactionGridRow(row, rowIndex: rowIndex)
                        }
                    }
                }
                .frame(maxHeight: Metrics.expandedReactionsMaxHeight)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))

                HStack {
                    Spacer(minLength: 0)
                    expandReactionsButton
                        .frame(width: Metrics.expandButtonWidth)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            } else {
                LazyVGrid(columns: reactionColumns, spacing: Metrics.reactionsGridSpacing) {
                    ForEach(Array(ChatQuickReactions.compactPreview.enumerated()), id: \.offset) { index, emoji in
                        reactionButton(emoji, id: "compact-\(index)", index: index)
                    }
                    expandReactionsButton
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Metrics.reactionsPaddingHorizontal)
        .padding(.vertical, Metrics.reactionsPaddingVertical)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.reactionsCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.reactionsCornerRadius, style: .continuous)
                .strokeBorder(Color.glassBorderHighlight.opacity(Metrics.panelBorderOpacity), lineWidth: 1)
        }
        .shadow(
            color: Color.discoverCardShadow.opacity(Metrics.shadowOpacity),
            radius: Metrics.shadowRadius,
            x: 0,
            y: Metrics.shadowYOffset
        )
        .animation(Metrics.expansionAnimation, value: areReactionsExpanded)
        // Пункт 3: собираем координаты всех кнопок и следим за драгом пальца поверх грида.
        .coordinateSpace(name: Metrics.reactionsCoordinateSpace)
        .onPreferenceChange(ReactionFramePreferenceKey.self) { anchors in
            // Разворачивается ниже, в overlayPreferenceValue, где есть доступ к GeometryProxy.
        }
        .overlayPreferenceValue(ReactionFramePreferenceKey.self) { anchors in
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: anchors.count) { _, _ in
                        updateFrames(anchors, proxy: proxy)
                    }
                    .onAppear {
                        updateFrames(anchors, proxy: proxy)
                    }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: Metrics.magnifyDragActivationDistance, coordinateSpace: .named(Metrics.reactionsCoordinateSpace))
                .onChanged { value in
                    guard !areReactionsExpanded else {
                        resetMagnifyState(animated: false)
                        return
                    }
                    dragLocation = value.location
                    updateActiveMagnifiedID(for: value.location)
                }
                .onEnded { _ in
                    guard !areReactionsExpanded else {
                        resetMagnifyState()
                        return
                    }
                    if let activeMagnifiedID, let emoji = emoji(forID: activeMagnifiedID) {
                        ChatQuickReactions.recordUsage(emoji)
                        performMenuAction(onReact, emoji)
                    }
                    resetMagnifyState()
                }
        )
    }

    private func reactionGridRow(_ row: [String], rowIndex: Int) -> some View {
        LazyVGrid(columns: reactionColumns, spacing: Metrics.reactionsGridSpacing) {
            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, emoji in
                reactionButton(
                    emoji,
                    id: "row\(rowIndex)-col\(colIndex)",
                    index: rowIndex * 6 + colIndex
                )
            }
        }
    }

    private var expandReactionsButton: some View {
        Button {
            triggerHaptic()
            areReactionsExpanded.toggle()
        } label: {
            Image(systemName: areReactionsExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: Metrics.expandButtonIconSize, weight: .semibold))
                .foregroundStyle(Color.discoverViolet)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.reactionButtonSize)
                .background(
                    Circle()
                        .fill(Color.cardSurface.opacity(Metrics.reactionIconFillOpacity))
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            Color.glassBorderHighlight.opacity(Metrics.reactionBorderOpacity),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.spring(pressedScale: Metrics.pressedScale))
        .accessibilityLabel(String(localized: "chats.action.react_more"))
    }

    private var actionsPanel: some View {
        VStack(spacing: 0) {
            if message.canReply {
                actionRow(title: "chats.action.reply", icon: "arrowshape.turn.up.left.fill", action: onReply)
                rowDivider
            }
            if message.canCopy {
                actionRow(title: "chats.action.copy", icon: "doc.on.doc", action: onCopy)
                rowDivider
            }
            if message.canEdit {
                actionRow(title: "chats.action.edit", icon: "pencil", action: onEdit)
                rowDivider
            }
            if message.canCancelPendingOutgoing || message.canDelete {
                actionRow(
                    title: "chats.action.delete",
                    icon: "trash",
                    tint: Color.error,
                    action: onDelete
                )
            }
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                .strokeBorder(Color.glassBorderHighlight.opacity(Metrics.panelBorderOpacity), lineWidth: 1)
        }
        .shadow(
            color: Color.discoverCardShadow.opacity(Metrics.shadowOpacity),
            radius: Metrics.shadowRadius,
            x: 0,
            y: Metrics.shadowYOffset
        )
    }

    private var panelBackground: some View {
        ZStack {
            Color.discoverBackgroundGradient
            LinearGradient(
                colors: [
                    Color.brandPrimaryGlow.opacity(colorScheme == .dark
                        ? Metrics.panelGradientPrimaryDark
                        : Metrics.panelGradientPrimaryLight),
                    Color.clear,
                    Color.discoverViolet.opacity(colorScheme == .dark
                        ? Metrics.panelGradientAccentDark
                        : Metrics.panelGradientAccentLight),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Color.cardSurface.opacity(colorScheme == .dark
                ? Metrics.panelSurfaceOpacityDark
                : Metrics.panelSurfaceOpacityLight)
        }
    }

    // MARK: - Reaction button (Пункты 1, 2, 3, 4)

    private func reactionButton(_ emoji: String, id: String, index: Int) -> some View {
        ReactionEmojiButton(
            emoji: emoji,
            index: index,
            isCurrentUserReaction: resolvedCurrentReactionEmoji == ReactionEmoji.normalized(emoji),
            magnifyScale: magnifyScale(for: id),
            size: Metrics.reactionButtonSize,
            emojiFontSize: Metrics.reactionEmojiSize,
            entranceDelayStep: Metrics.entranceStaggerStep
        ) {
            ChatQuickReactions.recordUsage(emoji)
            performMenuAction(onReact, emoji)
        }
        .anchorPreference(key: ReactionFramePreferenceKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }

    private func actionRow(
        title: LocalizedStringResource,
        icon: String,
        tint: Color = Color.discoverViolet,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            performMenuAction(action)
        } label: {
            HStack(spacing: Metrics.actionRowSpacing) {
                Image(systemName: icon)
                    .font(.system(size: Metrics.actionIconSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: Metrics.actionIconFrame)

                Text(title)
                    .font(Font.App.manrope(size: Metrics.actionTextSize, weight: .semibold))
                    .foregroundStyle(tint == Color.error ? Color.error : Color.primaryText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, Metrics.actionRowPaddingVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChatPressableRowStyle())
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.hairline.opacity(Metrics.hairlineOpacity))
            .frame(height: Metrics.hairlineHeight)
    }

    // MARK: - Magnify helpers (Пункт 3)

    private func updateFrames(_ anchors: [String: Anchor<CGRect>], proxy: GeometryProxy) {
        var resolved: [String: CGRect] = [:]
        for (id, anchor) in anchors {
            resolved[id] = proxy[anchor]
        }
        reactionFrames = resolved
    }

    private func updateActiveMagnifiedID(for location: CGPoint) {
        var closestID: String? = nil
        var closestDistance: CGFloat = .greatestFiniteMagnitude

        for (id, frame) in reactionFrames {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let distance = hypot(center.x - location.x, center.y - location.y)
            if distance < closestDistance {
                closestDistance = distance
                closestID = id
            }
        }

        let newActiveID = closestDistance < Metrics.magnifyRadius ? closestID : nil
        if newActiveID != activeMagnifiedID {
            triggerHaptic(style: .light)
            activeMagnifiedID = newActiveID
        }
    }

    private func magnifyScale(for id: String) -> CGFloat {
        guard let dragLocation, let frame = reactionFrames[id] else { return 1.0 }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let distance = hypot(center.x - dragLocation.x, center.y - dragLocation.y)
        guard distance < Metrics.magnifyRadius else { return 1.0 }
        let proximity = 1 - (distance / Metrics.magnifyRadius)
        return 1.0 + proximity * (Metrics.magnifyMaxScale - 1.0)
    }

    private func resetMagnifyState(animated: Bool = true) {
        let reset = {
            dragLocation = nil
            activeMagnifiedID = nil
        }

        if animated {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78), reset)
        } else {
            reset()
        }
    }

    private func emoji(forID id: String) -> String? {
        if id.hasPrefix("compact-"), let index = Int(id.dropFirst("compact-".count)) {
            return ChatQuickReactions.compactPreview[safe: index]
        }
        if let range = id.range(of: "col") {
            let colString = id[range.upperBound...]
            if let colIndex = Int(colString),
               let rowRange = id.range(of: "row"),
               let dashRange = id.range(of: "-col") {
                let rowString = id[rowRange.upperBound..<dashRange.lowerBound]
                if let rowIndex = Int(rowString) {
                    return ChatQuickReactions.rows[safe: rowIndex]?[safe: colIndex]
                }
            }
        }
        return nil
    }

    // MARK: - Actions

    #if canImport(UIKit)
    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        HapticFeedback.impact(style)
    }
    #else
    private func triggerHaptic() {}
    #endif

    private func performMenuAction(_ action: () -> Void) {
        triggerHaptic()
        action()
    }

    private func performMenuAction<T>(_ action: (T) -> Void, _ value: T) {
        triggerHaptic()
        action(value)
    }
}

// MARK: - Reaction emoji button subview (Пункты 1, 2, 4)

private struct ReactionEmojiButton: View {
    let emoji: String
    let index: Int
    let isCurrentUserReaction: Bool
    let magnifyScale: CGFloat
    let size: CGFloat
    let emojiFontSize: CGFloat
    let entranceDelayStep: Double
    let action: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: emojiFontSize))
                .frame(maxWidth: .infinity)
                .frame(height: size)
                // Пункт 4: тонкое кольцо-хайлайт вокруг реакции, которую уже поставил юзер.
                .background(
                    Circle()
                        .fill(isCurrentUserReaction ? Color.discoverViolet.opacity(0.16) : Color.clear)
                )
                .overlay {
                    if isCurrentUserReaction {
                        Circle()
                            .strokeBorder(Color.discoverViolet, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        // Пункт 1: убрали серую подложку-круг — эмодзи "дышит" свободно.
        // Пункт 3: локальный magnify-скейл, управляемый драгом пальца из родителя.
        .scaleEffect(hasAppeared ? magnifyScale : 0.3)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.68), value: magnifyScale)
        .onAppear {
            // Пункт 2: staggered-появление — эмодзи выпрыгивают по очереди, а не разом.
            withAnimation(
                .spring(response: 0.22, dampingFraction: 0.72)
                    .delay(Double(index) * entranceDelayStep)
            ) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Preference key for magnify gesture (Пункт 3)

private struct ReactionFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Safe array subscript helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Metrics

private extension ChatMessageContextMenuOverlay {
    enum Metrics {
        static let panelWidth: CGFloat = 280
        static let panelGap: CGFloat = 10
        static let previewBubbleMaxWidth: CGFloat = 360
        static let centerHorizontalPadding: CGFloat = 24
        static let centerVerticalPadding: CGFloat = 24

        static let reactionsCornerRadius: CGFloat = 22
        static let reactionsGridSpacing: CGFloat = 6
        static let reactionsVStackSpacing: CGFloat = 8
        static let reactionsPaddingHorizontal: CGFloat = 12
        static let reactionsPaddingVertical: CGFloat = 12

        static let reactionButtonSize: CGFloat = 40
        static let expandedReactionVisibleRows: CGFloat = 4
        static let reactionEmojiSize: CGFloat = 24
        static let expandButtonWidth: CGFloat = 46
        static let expandButtonIconSize: CGFloat = 14

        static var expandedReactionsMaxHeight: CGFloat {
            reactionButtonSize * expandedReactionVisibleRows
                + reactionsVStackSpacing * max(0, expandedReactionVisibleRows - 1)
        }

        static let actionRowSpacing: CGFloat = 12
        static let actionIconSize: CGFloat = 17
        static let actionIconFrame: CGFloat = 24
        static let actionTextSize: CGFloat = 16
        static let actionRowPaddingVertical: CGFloat = 13
        static let actionRowHeight: CGFloat = 50

        static let pressedScale: CGFloat = 0.9

        static let shadowRadius: CGFloat = 12
        static let shadowYOffset: CGFloat = 4
        static let shadowOpacity: CGFloat = 0.18

        static let panelBorderOpacity: CGFloat = 0.28
        static let reactionBorderOpacity: CGFloat = 0.22
        static let reactionIconFillOpacity: CGFloat = 0.3
        static let panelSurfaceOpacityDark: CGFloat = 0.20
        static let panelSurfaceOpacityLight: CGFloat = 0.30
        static let panelGradientPrimaryDark: CGFloat = 0.10
        static let panelGradientPrimaryLight: CGFloat = 0.14
        static let panelGradientAccentDark: CGFloat = 0.08
        static let panelGradientAccentLight: CGFloat = 0.10

        static let dimmingTintDark: CGFloat = 0.18
        static let dimmingTintLight: CGFloat = 0.14
        static let hairlineOpacity: CGFloat = 0.85

        // Пункт 2: шаг задержки между появлением соседних эмодзи.
        static let entranceStaggerStep: Double = 0.006

        // Пункт 3: параметры magnify-эффекта.
        static let reactionsCoordinateSpace: String = "reactionsGrid"
        static let magnifyDragActivationDistance: CGFloat = 8
        static let magnifyRadius: CGFloat = 46
        static let magnifyMaxScale: CGFloat = 1.55

        static var hairlineHeight: CGFloat {
            #if canImport(UIKit)
            1.0 / UIScreen.main.scale
            #else
            1.0
            #endif
        }

        static var expansionAnimation: Animation {
            .interpolatingSpring(stiffness: 300, damping: 25)
        }
    }
}

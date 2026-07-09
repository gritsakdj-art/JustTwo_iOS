import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ChatMessageContextMenuOverlay: View {
    let message: ChatMessage
    let anchor: CGRect
    let onReply: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReact: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var areReactionsExpanded = false

    private var reactionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Metrics.reactionsGridSpacing), count: 6)
    }

    var body: some View {
        GeometryReader { geometry in
            let localAnchor = anchorInLocalSpace(anchor, container: geometry)
            let contentTop = effectiveContentTop(in: geometry)
            let contentBottom = effectiveContentBottom(in: geometry)
            let panelLeadingX = panelLeadingX(in: geometry, localAnchor: localAnchor)
            let placement = menuPlacement(
                anchor: localAnchor,
                contentTop: contentTop,
                contentBottom: contentBottom,
                containerHeight: geometry.size.height
            )
            let positions = panelPositions(
                placement: placement,
                anchor: localAnchor,
                contentTop: contentTop,
                contentBottom: contentBottom,
                containerHeight: geometry.size.height
            )
            let cutout = messageCutoutRect(for: localAnchor)

            ZStack(alignment: .topLeading) {
                dimmingBackground(cutout: cutout)
                    .onTapGesture(perform: onDismiss)

                messageCutoutGlow(cutout: cutout)

                if message.canReact, let reactionsY = positions.reactionsCenterY {
                    reactionsPanel
                        .frame(width: Metrics.panelWidth)
                        .position(
                            x: panelLeadingX + Metrics.panelWidth / 2,
                            y: reactionsY
                        )
                }

                actionsPanel
                    .frame(width: Metrics.panelWidth)
                    .position(
                        x: panelLeadingX + Metrics.panelWidth / 2,
                        y: positions.actionsCenterY
                    )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            areReactionsExpanded = false
        }
        .transition(.opacity)
    }

    // MARK: - Background

    private func dimmingBackground(cutout: CGRect) -> some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Rectangle()
                .fill(colorScheme == .dark
                    ? Color.black.opacity(Metrics.dimmingTintDark)
                    : Color.white.opacity(Metrics.dimmingTintLight))
        }
        .mask {
            Rectangle()
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.messageCutoutCornerRadius, style: .continuous)
                        .frame(width: cutout.width, height: cutout.height)
                        .position(x: cutout.midX, y: cutout.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
        .ignoresSafeArea()
    }

    private func messageCutoutGlow(cutout: CGRect) -> some View {
        RoundedRectangle(cornerRadius: Metrics.messageCutoutCornerRadius, style: .continuous)
            .strokeBorder(
                Color.white.opacity(colorScheme == .dark
                    ? Metrics.messageCutoutStrokeOpacityDark
                    : Metrics.messageCutoutStrokeOpacityLight),
                lineWidth: Metrics.messageCutoutStrokeWidth
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark
                    ? Metrics.messageCutoutShadowOpacityDark
                    : Metrics.messageCutoutShadowOpacityLight),
                radius: Metrics.messageCutoutShadowRadius,
                y: Metrics.messageCutoutShadowYOffset
            )
            .frame(width: cutout.width, height: cutout.height)
            .position(x: cutout.midX, y: cutout.midY)
            .allowsHitTesting(false)
    }

    private func messageCutoutRect(for anchor: CGRect) -> CGRect {
        anchor.insetBy(
            dx: -Metrics.messageCutoutPadding,
            dy: -Metrics.messageCutoutPadding
        )
    }

    // MARK: - Panels

    private var reactionsPanel: some View {
        VStack(alignment: .leading, spacing: Metrics.reactionsVStackSpacing) {
            if areReactionsExpanded {
                ForEach(Array(ChatQuickReactions.rows.enumerated()), id: \.offset) { _, row in
                    LazyVGrid(columns: reactionColumns, spacing: Metrics.reactionsGridSpacing) {
                        ForEach(row, id: \.self) { emoji in
                            reactionButton(emoji)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                HStack {
                    Spacer(minLength: 0)
                    expandReactionsButton
                        .frame(width: Metrics.expandButtonWidth)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            } else {
                LazyVGrid(columns: reactionColumns, spacing: Metrics.reactionsGridSpacing) {
                    ForEach(ChatQuickReactions.compactPreview, id: \.self) { emoji in
                        reactionButton(emoji)
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

    private func reactionButton(_ emoji: String) -> some View {
        Button {
            performMenuAction(onReact, emoji)
        } label: {
            Text(emoji)
                .font(.system(size: Metrics.reactionEmojiSize))
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

    // MARK: - Actions

    private func triggerHaptic() {
        #if canImport(UIKit)
        HapticFeedback.impact(.light)
        #endif
    }

    private func performMenuAction(_ action: () -> Void) {
        triggerHaptic()
        action()
    }

    private func performMenuAction<T>(_ action: (T) -> Void, _ value: T) {
        triggerHaptic()
        action(value)
    }

    // MARK: - Placement

    private enum MenuPlacement {
        case split
        case bothBelow
        case bothAbove
    }

    private struct PanelPositions {
        var reactionsCenterY: CGFloat?
        var actionsCenterY: CGFloat
    }

    private func menuPlacement(
        anchor: CGRect,
        contentTop: CGFloat,
        contentBottom: CGFloat,
        containerHeight: CGFloat
    ) -> MenuPlacement {
        let expandedReactionsHeight = reactionsPanelHeight(expanded: true)
        let actionsHeight = actionsPanelHeight
        let spaceAbove = anchor.minY - contentTop
        let spaceBelow = containerHeight - contentBottom - anchor.maxY

        if message.canReact, spaceAbove < expandedReactionsHeight + Metrics.panelGap {
            return .bothBelow
        }

        let canFitSplit = message.canReact
            ? spaceAbove >= expandedReactionsHeight + Metrics.panelGap
                && spaceBelow >= actionsHeight + Metrics.panelGap
            : spaceBelow >= actionsHeight + Metrics.panelGap

        if canFitSplit {
            return .split
        }

        let stackHeight = message.canReact
            ? expandedReactionsHeight + Metrics.panelGap + actionsHeight
            : actionsHeight

        if spaceBelow >= stackHeight + Metrics.panelGap {
            return .bothBelow
        }

        if spaceAbove >= stackHeight + Metrics.panelGap {
            return .bothAbove
        }

        return spaceBelow >= spaceAbove ? .bothBelow : .bothAbove
    }

    private func panelPositions(
        placement: MenuPlacement,
        anchor: CGRect,
        contentTop: CGFloat,
        contentBottom: CGFloat,
        containerHeight: CGFloat
    ) -> PanelPositions {
        let reactionsH = reactionsPanelHeight(expanded: areReactionsExpanded)
        let actionsH = actionsPanelHeight

        switch placement {
        case .split:
            let reactionsY = message.canReact
                ? clampCenterY(
                    anchor.minY - Metrics.panelGap - reactionsH / 2,
                    panelHeight: reactionsH,
                    contentTop: contentTop,
                    contentBottom: contentBottom,
                    containerHeight: containerHeight
                )
                : nil
            let actionsY = clampCenterY(
                anchor.maxY + Metrics.panelGap + actionsH / 2,
                panelHeight: actionsH,
                contentTop: contentTop,
                contentBottom: contentBottom,
                containerHeight: containerHeight
            )
            return PanelPositions(reactionsCenterY: reactionsY, actionsCenterY: actionsY)

        case .bothBelow:
            var cursor = anchor.maxY + Metrics.panelGap
            var reactionsY: CGFloat?
            if message.canReact {
                reactionsY = cursor + reactionsH / 2
                cursor += reactionsH + Metrics.panelGap
            }
            let actionsY = cursor + actionsH / 2
            return clampStack(
                reactionsCenterY: reactionsY,
                actionsCenterY: actionsY,
                reactionsHeight: reactionsH,
                actionsHeight: actionsH,
                contentTop: contentTop,
                contentBottom: contentBottom,
                containerHeight: containerHeight
            )

        case .bothAbove:
            var cursor = anchor.minY - Metrics.panelGap
            let actionsY = cursor - actionsH / 2
            cursor -= actionsH + Metrics.panelGap
            var reactionsY: CGFloat?
            if message.canReact {
                reactionsY = cursor - reactionsH / 2
            }
            return clampStack(
                reactionsCenterY: reactionsY,
                actionsCenterY: actionsY,
                reactionsHeight: reactionsH,
                actionsHeight: actionsH,
                contentTop: contentTop,
                contentBottom: contentBottom,
                containerHeight: containerHeight
            )
        }
    }

    private func clampCenterY(
        _ centerY: CGFloat,
        panelHeight: CGFloat,
        contentTop: CGFloat,
        contentBottom: CGFloat,
        containerHeight: CGFloat
    ) -> CGFloat {
        let minY = contentTop + panelHeight / 2
        let maxY = containerHeight - contentBottom - panelHeight / 2
        return min(max(centerY, minY), maxY)
    }

    private func clampStack(
        reactionsCenterY: CGFloat?,
        actionsCenterY: CGFloat,
        reactionsHeight: CGFloat,
        actionsHeight: CGFloat,
        contentTop: CGFloat,
        contentBottom: CGFloat,
        containerHeight: CGFloat
    ) -> PanelPositions {
        let stackTop: CGFloat
        let stackBottom: CGFloat

        if let reactionsCenterY {
            stackTop = reactionsCenterY - reactionsHeight / 2
            stackBottom = actionsCenterY + actionsHeight / 2
        } else {
            stackTop = actionsCenterY - actionsHeight / 2
            stackBottom = actionsCenterY + actionsHeight / 2
        }

        let minTop = contentTop
        let maxBottom = containerHeight - contentBottom
        var offset: CGFloat = 0

        if stackBottom > maxBottom {
            offset = maxBottom - stackBottom
        } else if stackTop < minTop {
            offset = minTop - stackTop
        }

        return PanelPositions(
            reactionsCenterY: reactionsCenterY.map { $0 + offset },
            actionsCenterY: actionsCenterY + offset
        )
    }

    private func effectiveContentTop(in geometry: GeometryProxy) -> CGFloat {
        let containerMinY = geometry.frame(in: .global).minY
        let headerBottomY = geometry.safeAreaInsets.top + Metrics.navigationBarHeight
        let obstructionInLocal = max(0, headerBottomY - containerMinY)
        return obstructionInLocal + Metrics.safeAreaPadding
    }

    private func effectiveContentBottom(in geometry: GeometryProxy) -> CGFloat {
        geometry.safeAreaInsets.bottom + Metrics.safeAreaPadding
    }

    private func anchorInLocalSpace(_ anchor: CGRect, container: GeometryProxy) -> CGRect {
        let origin = container.frame(in: .global).origin
        return anchor.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    private func panelLeadingX(in geometry: GeometryProxy, localAnchor: CGRect) -> CGFloat {
        let maxX = geometry.size.width - Metrics.panelWidth - Metrics.panelMargin

        if message.isMine {
            return max(Metrics.panelMargin, min(localAnchor.maxX - Metrics.panelWidth, maxX))
        }
        return max(Metrics.panelMargin, min(localAnchor.minX, maxX))
    }

    private func reactionsPanelHeight(expanded: Bool) -> CGFloat {
        let verticalPadding = Metrics.reactionsPaddingVertical * 2

        guard expanded else {
            return verticalPadding + Metrics.reactionButtonSize
        }

        let rowCount = CGFloat(ChatQuickReactions.rows.count)
        let gridRows = rowCount * Metrics.reactionButtonSize
            + max(0, rowCount - 1) * Metrics.reactionsVStackSpacing
        let expandRow = Metrics.reactionButtonSize
        let interBlockSpacing = Metrics.reactionsVStackSpacing

        return verticalPadding + gridRows + interBlockSpacing + expandRow
    }

    private var actionsPanelHeight: CGFloat {
        var rows = 0
        if message.canReply { rows += 1 }
        if message.canCopy { rows += 1 }
        if message.canEdit { rows += 1 }
        if message.canDelete { rows += 1 }
        return CGFloat(rows) * Metrics.actionRowHeight
    }
}

// MARK: - Metrics

private extension ChatMessageContextMenuOverlay {
    enum Metrics {
        static let panelWidth: CGFloat = 280
        static let panelGap: CGFloat = 10
        static let panelMargin: CGFloat = 16
        static let safeAreaPadding: CGFloat = 8
        static let navigationBarHeight: CGFloat = 44

        static let reactionsCornerRadius: CGFloat = 22
        static let reactionsGridSpacing: CGFloat = 6
        static let reactionsVStackSpacing: CGFloat = 8
        static let reactionsPaddingHorizontal: CGFloat = 12
        static let reactionsPaddingVertical: CGFloat = 12

        static let reactionButtonSize: CGFloat = 40
        static let reactionEmojiSize: CGFloat = 24
        static let expandButtonWidth: CGFloat = 46
        static let expandButtonIconSize: CGFloat = 14

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
        static let dimmingTintLight: CGFloat = 0.06
        static let hairlineOpacity: CGFloat = 0.85

        static let messageCutoutPadding: CGFloat = 6
        static let messageCutoutCornerRadius: CGFloat = 18
        static let messageCutoutStrokeWidth: CGFloat = 1
        static let messageCutoutStrokeOpacityDark: CGFloat = 0.14
        static let messageCutoutStrokeOpacityLight: CGFloat = 0.38
        static let messageCutoutShadowRadius: CGFloat = 10
        static let messageCutoutShadowYOffset: CGFloat = 4
        static let messageCutoutShadowOpacityDark: CGFloat = 0.32
        static let messageCutoutShadowOpacityLight: CGFloat = 0.16

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

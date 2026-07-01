import SwiftUI

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

    private let reactionColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
    private let panelWidth: CGFloat = 312
    private let panelGap: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let localAnchor = anchorInLocalSpace(anchor, container: geometry)
            let safeTop = geometry.safeAreaInsets.top + 8
            let safeBottom = geometry.safeAreaInsets.bottom + 8
            let panelLeadingX = panelLeadingX(in: geometry, localAnchor: localAnchor)
            let placement = menuPlacement(
                anchor: localAnchor,
                safeTop: safeTop,
                safeBottom: safeBottom,
                containerHeight: geometry.size.height
            )
            let positions = panelPositions(
                placement: placement,
                anchor: localAnchor,
                safeTop: safeTop,
                safeBottom: safeBottom,
                containerHeight: geometry.size.height
            )

            ZStack(alignment: .topLeading) {
                Color.black.opacity(colorScheme == .dark ? 0.44 : 0.28)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                if message.canReact, let reactionsY = positions.reactionsCenterY {
                    reactionsPanel
                        .frame(width: panelWidth)
                        .position(
                            x: panelLeadingX + panelWidth / 2,
                            y: reactionsY
                        )
                }

                actionsPanel
                    .frame(width: panelWidth)
                    .position(
                        x: panelLeadingX + panelWidth / 2,
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

    private var reactionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if areReactionsExpanded {
                ForEach(Array(ChatQuickReactions.rows.enumerated()), id: \.offset) { _, row in
                    LazyVGrid(columns: reactionColumns, spacing: 6) {
                        ForEach(row, id: \.self) { emoji in
                            reactionButton(emoji)
                        }
                    }
                }

                HStack {
                    Spacer(minLength: 0)
                    expandReactionsButton
                        .frame(width: 46)
                    Spacer(minLength: 0)
                }
            } else {
                LazyVGrid(columns: reactionColumns, spacing: 6) {
                    ForEach(ChatQuickReactions.compactPreview, id: \.self) { emoji in
                        reactionButton(emoji)
                    }
                    expandReactionsButton
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.glassBorderHighlight.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: Color.discoverCardShadow.opacity(0.18), radius: 18, x: 0, y: 8)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: areReactionsExpanded)
    }

    private var expandReactionsButton: some View {
        Button {
            #if canImport(UIKit)
            HapticFeedback.impact(.light)
            #endif
            areReactionsExpanded.toggle()
        } label: {
            Image(systemName: areReactionsExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.discoverViolet)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Circle()
                        .fill(Color.cardSurface.opacity(colorScheme == .dark ? 0.55 : 0.72))
                )
                .overlay {
                    Circle()
                        .strokeBorder(Color.glassBorderHighlight.opacity(0.22), lineWidth: 1)
                }
        }
        .buttonStyle(.spring(pressedScale: 0.9))
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
            if message.canDelete {
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
                .strokeBorder(Color.glassBorderHighlight.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: Color.discoverCardShadow.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    private var panelBackground: some View {
        ZStack {
            Color.discoverBackgroundGradient
            LinearGradient(
                colors: [
                    Color.brandPrimaryGlow.opacity(colorScheme == .dark ? 0.10 : 0.14),
                    Color.clear,
                    Color.discoverViolet.opacity(colorScheme == .dark ? 0.08 : 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Color.cardSurface.opacity(colorScheme == .dark ? 0.20 : 0.30)
        }
    }

    private func reactionButton(_ emoji: String) -> some View {
        Button {
            performMenuAction(onReact, emoji)
        } label: {
            Text(emoji)
                .font(.system(size: 24))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Circle()
                        .fill(Color.cardSurface.opacity(colorScheme == .dark ? 0.55 : 0.72))
                )
                .overlay {
                    Circle()
                        .strokeBorder(Color.glassBorderHighlight.opacity(0.22), lineWidth: 1)
                }
        }
        .buttonStyle(.spring(pressedScale: 0.9))
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
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24)

                Text(title)
                    .font(Font.App.manrope(size: 16, weight: .semibold))
                    .foregroundStyle(tint == Color.error ? Color.error : Color.primaryText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChatPressableRowStyle())
    }

    private var rowDivider: some View {
        Divider().overlay(Color.hairline.opacity(0.85))
    }

    private func performMenuAction(_ action: () -> Void) {
        #if canImport(UIKit)
        HapticFeedback.impact(.light)
        #endif
        action()
    }

    private func performMenuAction<T>(_ action: (T) -> Void, _ value: T) {
        #if canImport(UIKit)
        HapticFeedback.impact(.light)
        #endif
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
        safeTop: CGFloat,
        safeBottom: CGFloat,
        containerHeight: CGFloat
    ) -> MenuPlacement {
        let usableHeight = max(containerHeight - safeTop - safeBottom, 1)
        let relativeY = (anchor.midY - safeTop) / usableHeight

        if relativeY < 0.33 {
            return .bothBelow
        } else if relativeY > 0.66 {
            return .bothAbove
        } else {
            return .split
        }
    }

    private func panelPositions(
        placement: MenuPlacement,
        anchor: CGRect,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        containerHeight: CGFloat
    ) -> PanelPositions {
        let reactionsH = reactionsPanelHeight
        let actionsH = actionsPanelHeight

        switch placement {
        case .split:
            let reactionsY = message.canReact
                ? clampCenterY(
                    anchor.minY - panelGap - reactionsH / 2,
                    panelHeight: reactionsH,
                    safeTop: safeTop,
                    safeBottom: safeBottom,
                    containerHeight: containerHeight
                )
                : nil
            let actionsY = clampCenterY(
                anchor.maxY + panelGap + actionsH / 2,
                panelHeight: actionsH,
                safeTop: safeTop,
                safeBottom: safeBottom,
                containerHeight: containerHeight
            )
            return PanelPositions(reactionsCenterY: reactionsY, actionsCenterY: actionsY)

        case .bothBelow:
            var cursor = anchor.maxY + panelGap
            var reactionsY: CGFloat?
            if message.canReact {
                reactionsY = cursor + reactionsH / 2
                cursor += reactionsH + panelGap
            }
            let actionsY = cursor + actionsH / 2
            return clampStack(
                reactionsCenterY: reactionsY,
                actionsCenterY: actionsY,
                reactionsHeight: reactionsH,
                actionsHeight: actionsH,
                safeTop: safeTop,
                safeBottom: safeBottom,
                containerHeight: containerHeight
            )

        case .bothAbove:
            var cursor = anchor.minY - panelGap
            let actionsY = cursor - actionsH / 2
            cursor -= actionsH + panelGap
            var reactionsY: CGFloat?
            if message.canReact {
                reactionsY = cursor - reactionsH / 2
            }
            return clampStack(
                reactionsCenterY: reactionsY,
                actionsCenterY: actionsY,
                reactionsHeight: reactionsH,
                actionsHeight: actionsH,
                safeTop: safeTop,
                safeBottom: safeBottom,
                containerHeight: containerHeight
            )
        }
    }

    private func clampCenterY(
        _ centerY: CGFloat,
        panelHeight: CGFloat,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        containerHeight: CGFloat
    ) -> CGFloat {
        let minY = safeTop + panelHeight / 2
        let maxY = containerHeight - safeBottom - panelHeight / 2
        return min(max(centerY, minY), maxY)
    }

    private func clampStack(
        reactionsCenterY: CGFloat?,
        actionsCenterY: CGFloat,
        reactionsHeight: CGFloat,
        actionsHeight: CGFloat,
        safeTop: CGFloat,
        safeBottom: CGFloat,
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

        let minTop = safeTop
        let maxBottom = containerHeight - safeBottom
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

    private func anchorInLocalSpace(_ anchor: CGRect, container: GeometryProxy) -> CGRect {
        let origin = container.frame(in: .global).origin
        return anchor.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    private func panelLeadingX(in geometry: GeometryProxy, localAnchor: CGRect) -> CGFloat {
        let margin: CGFloat = 16
        let maxX = geometry.size.width - panelWidth - margin

        if message.isMine {
            return max(margin, min(localAnchor.maxX - panelWidth, maxX))
        }
        return max(margin, min(localAnchor.minX, maxX))
    }

    private var reactionsPanelHeight: CGFloat {
        if areReactionsExpanded {
            let rowCount = CGFloat(ChatQuickReactions.rows.count)
            return rowCount * 46 + 46 + 24
        }
        return 46 + 24
    }

    private var actionsPanelHeight: CGFloat {
        var rows = 0
        if message.canReply { rows += 1 }
        if message.canCopy { rows += 1 }
        if message.canEdit { rows += 1 }
        if message.canDelete { rows += 1 }
        return CGFloat(rows) * 50
    }
}

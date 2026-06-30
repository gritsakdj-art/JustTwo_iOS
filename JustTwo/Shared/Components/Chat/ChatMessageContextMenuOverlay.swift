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
    @State private var revealedReactionRows = 0

    private let reactionColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
    private let panelWidth: CGFloat = 312
    private let panelGap: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let localAnchor = anchorInLocalSpace(anchor, container: geometry)
            let safeTop = geometry.safeAreaInsets.top + 8
            let safeBottom = geometry.safeAreaInsets.bottom + 8
            let panelLeadingX = panelLeadingX(in: geometry, localAnchor: localAnchor)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(colorScheme == .dark ? 0.44 : 0.28)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                if message.canReact {
                    reactionsPanel
                        .frame(width: panelWidth)
                        .position(
                            x: panelLeadingX + panelWidth / 2,
                            y: clampedReactionsCenterY(
                                anchor: localAnchor,
                                safeTop: safeTop,
                                safeBottom: safeBottom,
                                containerHeight: geometry.size.height
                            )
                        )
                }

                actionsPanel
                    .frame(width: panelWidth)
                    .position(
                        x: panelLeadingX + panelWidth / 2,
                        y: clampedActionsCenterY(
                            anchor: localAnchor,
                            safeTop: safeTop,
                            safeBottom: safeBottom,
                            containerHeight: geometry.size.height
                        )
                    )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            animateReactionRowsIn()
        }
        .transition(.opacity)
    }

    private var reactionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ChatQuickReactions.rows.enumerated()), id: \.offset) { index, row in
                if index < revealedReactionRows {
                    LazyVGrid(columns: reactionColumns, spacing: 6) {
                        ForEach(row, id: \.self) { emoji in
                            reactionButton(emoji)
                        }
                    }
                    .transition(.scale(scale: 0.88, anchor: .bottom).combined(with: .opacity))
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

    private func animateReactionRowsIn() {
        revealedReactionRows = 0
        guard message.canReact else { return }

        for index in ChatQuickReactions.rows.indices {
            let delay = Double(index) * 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    revealedReactionRows = index + 1
                }
            }
        }
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

    private func clampedReactionsCenterY(
        anchor: CGRect,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        containerHeight: CGFloat
    ) -> CGFloat {
        let estimatedHeight = reactionsPanelHeight
        let preferred = anchor.minY - panelGap - estimatedHeight / 2
        let minY = safeTop + estimatedHeight / 2
        let maxY = containerHeight - safeBottom - estimatedHeight / 2
        return min(max(preferred, minY), maxY)
    }

    private func clampedActionsCenterY(
        anchor: CGRect,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        containerHeight: CGFloat
    ) -> CGFloat {
        let estimatedHeight = actionsPanelHeight
        let preferred = anchor.maxY + panelGap + estimatedHeight / 2
        let minY = safeTop + estimatedHeight / 2
        let maxY = containerHeight - safeBottom - estimatedHeight / 2
        return min(max(preferred, minY), maxY)
    }

    private var reactionsPanelHeight: CGFloat {
        let rowCount = CGFloat(max(revealedReactionRows, ChatQuickReactions.rows.count))
        return rowCount * 46 + 24
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

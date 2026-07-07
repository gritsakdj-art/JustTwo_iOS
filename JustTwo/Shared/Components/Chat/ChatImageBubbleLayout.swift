import CoreGraphics

/// Layout rules for image message bubbles in chat.
enum ChatImageBubbleLayout {
    nonisolated static let fallbackAspectRatio: CGFloat = 4.0 / 3.0
    nonisolated static let minWidth: CGFloat = 132
    nonisolated static let maxWidthCap: CGFloat = 280
    /// Landscape photos get a tighter width cap so they sit inside the bubble
    /// with a comfortable margin instead of hugging (or crossing) its edge.
    nonisolated static let landscapeMaxWidthCap: CGFloat = 232
    nonisolated static let minHeight: CGFloat = 120
    nonisolated static let maxHeight: CGFloat = 340
    nonisolated static let cornerRadius: CGFloat = 14

    /// Clamps extreme aspect ratios so portrait/landscape photos stay readable in chat.
    nonisolated static let minAspectRatio: CGFloat = 0.55
    nonisolated static let maxAspectRatio: CGFloat = 1.8

    nonisolated static func aspectRatio(width: Int, height: Int) -> CGFloat {
        guard width > 0, height > 0 else { return fallbackAspectRatio }
        let raw = CGFloat(width) / CGFloat(height)
        return min(maxAspectRatio, max(minAspectRatio, raw))
    }

    static func maxBubbleWidth(screenWidth: CGFloat) -> CGFloat {
        min(screenWidth * 0.68, maxWidthCap)
    }

    static func displaySize(
        width: Int,
        height: Int,
        maxBubbleWidth: CGFloat
    ) -> CGSize {
        let ratio = aspectRatio(width: width, height: height)
        let widthCap = ratio > 1 ? landscapeMaxWidthCap : maxWidthCap
        let cappedMaxWidth = min(maxBubbleWidth, widthCap)

        var bubbleWidth = cappedMaxWidth
        var bubbleHeight = bubbleWidth / ratio

        if bubbleHeight > maxHeight {
            bubbleHeight = maxHeight
            bubbleWidth = bubbleHeight * ratio
        }

        bubbleWidth = max(minWidth, min(cappedMaxWidth, bubbleWidth))
        bubbleHeight = max(minHeight, min(maxHeight, bubbleHeight))

        return CGSize(width: bubbleWidth, height: bubbleHeight)
    }

    static func displaySize(
        for attachment: ChatMessageAttachment,
        maxBubbleWidth: CGFloat
    ) -> CGSize {
        displaySize(width: attachment.width, height: attachment.height, maxBubbleWidth: maxBubbleWidth)
    }

    /// Small thumbnail (e.g. inside a reply preview): the long side is fixed,
    /// the short side follows the clamped aspect ratio.
    static func thumbnailSize(
        width: Int,
        height: Int,
        longSide: CGFloat = 100
    ) -> CGSize {
        let ratio = aspectRatio(width: width, height: height)
        if ratio >= 1 {
            return CGSize(width: longSide, height: (longSide / ratio).rounded())
        }
        return CGSize(width: (longSide * ratio).rounded(), height: longSide)
    }

    static func thumbnailSize(
        for attachment: ChatMessageAttachment,
        longSide: CGFloat = 100
    ) -> CGSize {
        thumbnailSize(width: attachment.width, height: attachment.height, longSide: longSide)
    }
}

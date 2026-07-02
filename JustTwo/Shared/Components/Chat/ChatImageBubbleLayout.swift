import CoreGraphics

/// Layout rules for image message bubbles in chat.
enum ChatImageBubbleLayout {
    static let fallbackAspectRatio: CGFloat = 4.0 / 3.0
    static let minWidth: CGFloat = 132
    static let maxWidthCap: CGFloat = 280
    /// Landscape photos get a tighter width cap so they sit inside the bubble
    /// with a comfortable margin instead of hugging (or crossing) its edge.
    static let landscapeMaxWidthCap: CGFloat = 232
    static let minHeight: CGFloat = 120
    static let maxHeight: CGFloat = 340
    static let cornerRadius: CGFloat = 14

    /// Clamps extreme aspect ratios so portrait/landscape photos stay readable in chat.
    private static let minAspectRatio: CGFloat = 0.55
    private static let maxAspectRatio: CGFloat = 1.8

    static func aspectRatio(width: Int, height: Int) -> CGFloat {
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

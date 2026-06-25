import SwiftUI

struct ChatBubbleShape: Shape {
    let isMine: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 16

        let tailW: CGFloat = 12
        let tailH: CGFloat = 18
        let tailInsetFromBottom: CGFloat = 14

        let body = CGRect(
            x: isMine ? rect.minX : rect.minX + tailW,
            y: rect.minY,
            width: rect.width - tailW,
            height: rect.height
        )

        let minX = body.minX
        let maxX = body.maxX
        let minY = body.minY
        let maxY = body.maxY

        let tailY2 = maxY - tailInsetFromBottom
        let tailY1 = tailY2 - tailH

        var path = Path()

        if isMine {
            path.move(to: CGPoint(x: minX + r, y: minY))

            path.addLine(to: CGPoint(x: maxX - r, y: minY))
            path.addQuadCurve(
                to: CGPoint(x: maxX, y: minY + r),
                control: CGPoint(x: maxX, y: minY)
            )

            path.addLine(to: CGPoint(x: maxX, y: tailY1))
            path.addQuadCurve(
                to: CGPoint(x: maxX + tailW, y: (tailY1 + tailY2) / 2),
                control: CGPoint(x: maxX, y: tailY1 + tailH * 0.25)
            )
            path.addQuadCurve(
                to: CGPoint(x: maxX, y: tailY2),
                control: CGPoint(x: maxX, y: tailY2 - tailH * 0.25)
            )

            path.addLine(to: CGPoint(x: maxX, y: maxY - r))
            path.addQuadCurve(
                to: CGPoint(x: maxX - r, y: maxY),
                control: CGPoint(x: maxX, y: maxY)
            )

            path.addLine(to: CGPoint(x: minX + r, y: maxY))
            path.addQuadCurve(
                to: CGPoint(x: minX, y: maxY - r),
                control: CGPoint(x: minX, y: maxY)
            )

            path.addLine(to: CGPoint(x: minX, y: minY + r))
            path.addQuadCurve(
                to: CGPoint(x: minX + r, y: minY),
                control: CGPoint(x: minX, y: minY)
            )
        } else {
            path.move(to: CGPoint(x: minX + r, y: minY))

            path.addLine(to: CGPoint(x: maxX - r, y: minY))
            path.addQuadCurve(
                to: CGPoint(x: maxX, y: minY + r),
                control: CGPoint(x: maxX, y: minY)
            )

            path.addLine(to: CGPoint(x: maxX, y: maxY - r))
            path.addQuadCurve(
                to: CGPoint(x: maxX - r, y: maxY),
                control: CGPoint(x: maxX, y: maxY)
            )

            path.addLine(to: CGPoint(x: minX + r, y: maxY))
            path.addQuadCurve(
                to: CGPoint(x: minX, y: maxY - r),
                control: CGPoint(x: minX, y: maxY)
            )

            path.addLine(to: CGPoint(x: minX, y: tailY2))
            path.addQuadCurve(
                to: CGPoint(x: minX - tailW, y: (tailY1 + tailY2) / 2),
                control: CGPoint(x: minX, y: tailY2 - tailH * 0.25)
            )
            path.addQuadCurve(
                to: CGPoint(x: minX, y: tailY1),
                control: CGPoint(x: minX, y: tailY1 + tailH * 0.25)
            )

            path.addLine(to: CGPoint(x: minX, y: minY + r))
            path.addQuadCurve(
                to: CGPoint(x: minX + r, y: minY),
                control: CGPoint(x: minX, y: minY)
            )
        }

        path.closeSubpath()
        return path
    }
}

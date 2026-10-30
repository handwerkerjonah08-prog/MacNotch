import SwiftUI

/// The island outline: concave flares where it meets the top of the screen and rounded bottom corners,
/// matching how the MacBook notch blends into the bezel.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(topRadius, rect.width / 4, rect.height / 2))
        let bodyWidth = rect.width - top * 2
        let bottom = max(0, min(bottomRadius, bodyWidth / 2, rect.height - top))
        // Cubic control offset that approximates a circular quarter arc.
        let k: CGFloat = 0.552

        let left = rect.minX + top
        let right = rect.maxX - top

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: left, y: rect.minY + top),
            control: CGPoint(x: left, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
        path.addCurve(
            to: CGPoint(x: left + bottom, y: rect.maxY),
            control1: CGPoint(x: left, y: rect.maxY - bottom + bottom * k),
            control2: CGPoint(x: left + bottom - bottom * k, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: right, y: rect.maxY - bottom),
            control1: CGPoint(x: right - bottom + bottom * k, y: rect.maxY),
            control2: CGPoint(x: right, y: rect.maxY - bottom + bottom * k)
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: right, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

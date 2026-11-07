import CoreGraphics
import Foundation

/// Shapes for the ornaments, shared by the layout manager (Core Graphics) and SwiftUI views.
nonisolated enum OrnamentPath {
    /// A filigree rule: two hairlines that taper toward a center diamond, with a dot on each
    /// side of it. Fills `rect`; the drawing is centered on its mid line.
    static func flourish(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let midY = rect.midY
        let centerX = rect.midX
        let diamond = max(2.5, rect.height / 2)
        let thickness = max(0.6, rect.height * 0.09)
        let dotRadius = max(0.9, rect.height * 0.13)
        let dotOffset = diamond * 2.2
        let lineGap = dotOffset + dotRadius * 2.5

        // Left and right tapers: thick near the center, a point at the outer end.
        if centerX - lineGap > rect.minX {
            path.move(to: CGPoint(x: rect.minX, y: midY))
            path.addLine(to: CGPoint(x: centerX - lineGap, y: midY - thickness))
            path.addLine(to: CGPoint(x: centerX - lineGap, y: midY + thickness))
            path.closeSubpath()

            path.move(to: CGPoint(x: rect.maxX, y: midY))
            path.addLine(to: CGPoint(x: centerX + lineGap, y: midY - thickness))
            path.addLine(to: CGPoint(x: centerX + lineGap, y: midY + thickness))
            path.closeSubpath()
        }

        path.move(to: CGPoint(x: centerX, y: midY - diamond))
        path.addLine(to: CGPoint(x: centerX + diamond, y: midY))
        path.addLine(to: CGPoint(x: centerX, y: midY + diamond))
        path.addLine(to: CGPoint(x: centerX - diamond, y: midY))
        path.closeSubpath()

        for side in [-1.0, 1.0] {
            let center = CGPoint(x: centerX + side * dotOffset, y: midY)
            path.addEllipse(in: CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        }
        return path
    }

    /// A blob of sealing wax: a circle whose edge swells and dips, as poured wax does.
    static func waxSeal(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let steps = 96
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let wobble = 1 + 0.06 * sin(9 * angle) + 0.03 * sin(4 * angle + 1.3)
            let r = Double(radius) * wobble
            let point = CGPoint(x: Double(center.x) + r * cos(angle), y: Double(center.y) + r * sin(angle))
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    /// A small diamond, used for bullets.
    static func diamond(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius * 0.8, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius * 0.8, y: center.y))
        path.closeSubpath()
        return path
    }
}

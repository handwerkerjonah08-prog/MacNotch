import Foundation

public struct RGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = RGB(red: 1, green: 1, blue: 1)
}

public struct HSB: Equatable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var brightness: Double
}

public enum ColorMath {
    public static func hsb(from rgb: RGB) -> HSB {
        let r = clamp(rgb.red), g = clamp(rgb.green), b = clamp(rgb.blue)
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue

        var hue = 0.0
        if delta > 0 {
            if maxValue == r {
                hue = (g - b) / delta
            } else if maxValue == g {
                hue = 2 + (b - r) / delta
            } else {
                hue = 4 + (r - g) / delta
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let saturation = maxValue == 0 ? 0 : delta / maxValue
        return HSB(hue: hue, saturation: saturation, brightness: maxValue)
    }

    public static func rgb(from hsb: HSB) -> RGB {
        let h = (hsb.hue - floor(hsb.hue)) * 6
        let s = clamp(hsb.saturation), v = clamp(hsb.brightness)
        let sector = Int(h) % 6
        let f = h - floor(h)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch sector {
        case 0: return RGB(red: v, green: t, blue: p)
        case 1: return RGB(red: q, green: v, blue: p)
        case 2: return RGB(red: p, green: v, blue: t)
        case 3: return RGB(red: p, green: q, blue: v)
        case 4: return RGB(red: t, green: p, blue: v)
        default: return RGB(red: v, green: p, blue: q)
        }
    }

    /// Turns an artwork's average color into a bright accent that reads well on black,
    /// the way iPhone tints the Dynamic Island waveform.
    public static func vibrantAccent(from average: RGB) -> RGB {
        var color = hsb(from: average)
        if color.saturation < 0.12 {
            // Near-gray artwork: use a soft white instead of a muddy tint.
            return RGB(red: 0.92, green: 0.92, blue: 0.94)
        }
        color.saturation = min(1, color.saturation * 1.35 + 0.15)
        color.brightness = min(0.98, max(0.72, color.brightness * 1.25))
        return rgb(from: color)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

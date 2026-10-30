import CoreGraphics
import Foundation

/// Where the notch is on a screen, in AppKit screen coordinates (origin bottom-left).
public struct NotchGeometry: Equatable, Sendable {
    public var notchRect: CGRect
    public var hasHardwareNotch: Bool

    public init(notchRect: CGRect, hasHardwareNotch: Bool) {
        self.notchRect = notchRect
        self.hasHardwareNotch = hasHardwareNotch
    }

    public var size: CGSize { notchRect.size }

    /// Matches the 15" MacBook Air notch so the island looks the same on external displays.
    public static let fallbackNotchWidth: CGFloat = 185

    /// - Parameters:
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top`; non-zero only on notched displays.
    ///   - auxiliaryLeftWidth/RightWidth: widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
    public static func compute(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryLeftWidth: CGFloat?,
        auxiliaryRightWidth: CGFloat?
    ) -> NotchGeometry {
        if safeAreaTop > 0,
           let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth,
           left > 0, right > 0 {
            let width = screenFrame.width - left - right
            if width > 40 {
                let rect = CGRect(
                    x: screenFrame.minX + left,
                    y: screenFrame.maxY - safeAreaTop,
                    width: width,
                    height: safeAreaTop
                )
                return NotchGeometry(notchRect: rect, hasHardwareNotch: true)
            }
        }

        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        let height = menuBarHeight >= 20 ? min(menuBarHeight, 44) : 32
        let width = fallbackNotchWidth
        let rect = CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
        return NotchGeometry(notchRect: rect, hasHardwareNotch: false)
    }
}

public struct CornerRadii: Equatable, Sendable {
    /// Concave flare where the island meets the top edge of the screen.
    public var top: CGFloat
    /// Convex rounding at the bottom of the island.
    public var bottom: CGFloat

    public init(top: CGFloat, bottom: CGFloat) {
        self.top = top
        self.bottom = bottom
    }
}

/// All island sizes in one place so the views, the window and the mouse tracking agree.
public enum IslandMetrics {
    public static let cardHeight: CGFloat = 132
    public static let cardSpacing: CGFloat = 10
    public static let contentPadding: CGFloat = 14
    public static let headerGap: CGFloat = 6
    public static let bottomPadding: CGFloat = 14
    public static let minHeaderSideWidth: CGFloat = 150

    public static let shortcutTileWidth: CGFloat = 52
    public static let shortcutTileSpacing: CGFloat = 8
    public static let shortcutCardPadding: CGFloat = 12

    public static func radii(for presentation: IslandPresentation) -> CornerRadii {
        switch presentation {
        case .idle: return CornerRadii(top: 6, bottom: 10)
        case .compactInfo, .compactNowPlaying: return CornerRadii(top: 6, bottom: 13)
        case .alert: return CornerRadii(top: 6, bottom: 14)
        case .expanded: return CornerRadii(top: 14, bottom: 32)
        }
    }

    public static func shortcutColumns(for count: Int) -> Int {
        min(max(Int((Double(count) / 2).rounded(.up)), 2), 4)
    }

    public static func cardWidth(for kind: WidgetKind, shortcutCount: Int) -> CGFloat {
        switch kind {
        case .nowPlaying: return 288
        case .weather: return 150
        case .fileShelf: return 196
        case .webPages:
            guard shortcutCount > 0 else { return 150 }
            let columns = CGFloat(shortcutColumns(for: shortcutCount))
            return shortcutCardPadding * 2 + columns * shortcutTileWidth + (columns - 1) * shortcutTileSpacing
        }
    }

    /// Width of the row of widget cards, without outer padding.
    public static func cardsRowWidth(widgets: [WidgetKind], shortcutCount: Int) -> CGFloat {
        guard !widgets.isEmpty else { return 280 }
        let cards = widgets.reduce(CGFloat(0)) { $0 + cardWidth(for: $1, shortcutCount: shortcutCount) }
        return cards + CGFloat(widgets.count - 1) * cardSpacing
    }

    public static func compactWingWidth(notch: CGSize) -> CGFloat {
        max(34, notch.height)
    }

    public static func alertWingWidth(for alert: AlertKind) -> CGFloat {
        switch alert {
        case .charging: return 104
        case .pluggedIn: return 112
        case .unplugged: return 112
        case .lowBattery: return 118
        case .shelfAdded: return 120
        case .shortcutAdded: return 120
        }
    }

    public static func infoWidth(for slot: NotchSlot) -> CGFloat {
        switch slot {
        case .none: return 0
        case .weather: return 64
        case .battery: return 70
        case .time: return 58
        case .date: return 66
        case .shelf: return 48
        }
    }

    /// Both wings share a width so the island stays centered on the notch.
    public static func infoWingWidth(leading: NotchSlot, trailing: NotchSlot) -> CGFloat {
        max(34, infoWidth(for: leading), infoWidth(for: trailing))
    }

    /// Full frame of the island shape including its top flares.
    public static func size(
        for presentation: IslandPresentation,
        notch: CGSize,
        widgets: [WidgetKind],
        shortcutCount: Int,
        maxWidth: CGFloat,
        leading: NotchSlot = .none,
        trailing: NotchSlot = .none
    ) -> CGSize {
        let flare = radii(for: presentation).top * 2
        let size: CGSize
        switch presentation {
        case .idle:
            size = CGSize(width: notch.width + flare, height: notch.height)
        case .compactInfo:
            let wing = infoWingWidth(leading: leading, trailing: trailing)
            size = CGSize(width: notch.width + wing * 2 + flare, height: notch.height)
        case .compactNowPlaying:
            size = CGSize(width: notch.width + compactWingWidth(notch: notch) * 2 + flare, height: notch.height)
        case .alert(let alert):
            size = CGSize(width: notch.width + alertWingWidth(for: alert) * 2 + flare, height: notch.height)
        case .expanded:
            let row = cardsRowWidth(widgets: widgets, shortcutCount: shortcutCount) + contentPadding * 2
            let headerMinimum = notch.width + minHeaderSideWidth * 2
            let height = notch.height + headerGap + cardHeight + bottomPadding
            size = CGSize(width: max(row, headerMinimum) + flare, height: height)
        }
        return CGSize(width: min(size.width, maxWidth), height: size.height)
    }

    /// Largest size the island can reach, used to size the transparent host window.
    public static func maximumSize(notch: CGSize, maxWidth: CGFloat) -> CGSize {
        let allWidgets = WidgetKind.allCases
        let expanded = size(for: .expanded, notch: notch, widgets: allWidgets, shortcutCount: 8, maxWidth: maxWidth)
        let alert = size(for: .alert(.shelfAdded(count: 0)), notch: notch, widgets: [], shortcutCount: 0, maxWidth: maxWidth)
        return CGSize(width: max(expanded.width, alert.width), height: expanded.height)
    }
}

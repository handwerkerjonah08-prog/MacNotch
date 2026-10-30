import AppKit
import NotchCore
import SwiftUI

/// Sample content for snapshots and the CI demo run.
enum DemoContent {
    static let track = TrackInfo(title: "Entropy", artist: "Beach Bunny", album: "Emotional Creature", duration: 221)

    static var weather: WeatherSnapshot {
        WeatherSnapshot(
            temperature: 54.4, apparentTemperature: 50.9, high: 61.2, low: 46.6,
            code: 2, isDay: true, humidity: 61, windSpeed: 9.4,
            unit: .fahrenheit, locationName: "Glencoe", fetchedAt: Date()
        )
    }

    static func artwork() -> NSImage {
        NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
            let gradient = NSGradient(colors: [
                NSColor(red: 0.98, green: 0.45, blue: 0.35, alpha: 1),
                NSColor(red: 0.85, green: 0.25, blue: 0.62, alpha: 1),
                NSColor(red: 0.35, green: 0.18, blue: 0.75, alpha: 1)
            ])
            gradient?.draw(in: rect, angle: -50)
            NSColor(white: 1, alpha: 0.22).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 140, dy: 140)).fill()
            NSColor(white: 1, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: NSRect(x: 360, y: 380, width: 120, height: 120)).fill()
            return true
        }
    }

    /// Writes a few real files so the shelf shows genuine Finder icons and thumbnails.
    static func makeShelfFiles() -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacNotchDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []

        let png = directory.appendingPathComponent("Thumbnail.png")
        if let tiff = artwork().tiffRepresentation,
           let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? data.write(to: png)
            urls.append(png)
        }

        let pdf = directory.appendingPathComponent("Project Brief.pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        if let context = CGContext(pdf as CFURL, mediaBox: &box, nil) {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.systemBlue.cgColor)
            context.fill(CGRect(x: 72, y: 560, width: 468, height: 160))
            context.setFillColor(NSColor.systemGray.cgColor)
            for line in 0..<8 {
                context.fill(CGRect(x: 72, y: 500 - line * 28, width: 468 - (line % 3) * 60, height: 10))
            }
            context.endPDFPage()
            context.closePDF()
            urls.append(pdf)
        }

        let notes = directory.appendingPathComponent("Notes.txt")
        try? "Ideas for the next update".write(to: notes, atomically: true, encoding: .utf8)
        urls.append(notes)

        return urls.reversed()
    }
}

/// Renders every island state to PNG so CI can check the visuals without a person.
@MainActor
public enum SnapshotRenderer {
    public static func renderAll(to directory: URL) -> Int32 {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 15" MacBook Air notch at the default display scaling.
        let notch = NotchGeometry(notchRect: CGRect(x: 640, y: 919, width: 190, height: 37), hasHardwareNotch: true)
        let settings = SettingsModel(preview: .default)
        let music = MusicController(live: false)
        let weather = WeatherService(live: false, location: .glencoe, unit: .fahrenheit)
        let battery = BatteryMonitor(live: false)
        let shelf = ShelfModel(live: false)
        let favicons = FaviconCache(live: true)

        music.preview(track: DemoContent.track, state: .playing, artwork: DemoContent.artwork(), elapsed: 170)
        weather.preview(DemoContent.weather)
        battery.preview(PowerSnapshot(level: 82, isCharging: true, isPluggedIn: true))
        let demoFiles = DemoContent.makeShelfFiles()
        shelf.add(demoFiles)
        favicons.load(settings.settings.shortcuts)

        let island = IslandViewModel(
            settings: settings, music: music, weather: weather,
            battery: battery, shelf: shelf, favicons: favicons,
            notch: notch, maxWidth: 1454
        )

        // Let favicons download and Quick Look thumbnails finish.
        spin(until: { favicons.icons.count >= settings.settings.shortcuts.count && shelf.thumbnails.count >= demoFiles.count }, timeout: 12)
        print("favicons loaded: \(favicons.icons.count)/\(settings.settings.shortcuts.count), thumbnails: \(shelf.thumbnails.count)/\(demoFiles.count)")

        var failures = 0
        func render(_ name: String, _ inputs: IslandInputs, height: CGFloat = 260) {
            island.forceInputs(inputs)
            let scene = SnapshotScene(model: island, canvas: CGSize(width: 1100, height: height))
                .environment(\.forceGlassFallback, true)
                .environment(\.isSnapshotRendering, true)
            let renderer = ImageRenderer(content: scene)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else {
                print("FAILED to render \(name)")
                failures += 1
                return
            }
            do {
                try data.write(to: directory.appendingPathComponent("\(name).png"))
                print("rendered \(name).png (\(image.width)x\(image.height)) presentation=\(island.presentation)")
            } catch {
                print("FAILED to write \(name): \(error)")
                failures += 1
            }
        }

        render("01-idle", IslandInputs(), height: 120)
        render("02-compact-now-playing", IslandInputs(nowPlayingActive: true), height: 120)
        render("03-alert-charging", IslandInputs(alert: .charging(level: 82)), height: 120)
        render("04-alert-low-battery", IslandInputs(alert: .lowBattery(level: 10)), height: 120)
        render("05-alert-shelf", IslandInputs(alert: .shelfAdded(count: 3)), height: 120)
        render("06-expanded-liquid-glass", IslandInputs(isPinnedOpen: true))

        settings.settings.glassTint = 0
        render("07-expanded-glass-clear", IslandInputs(isPinnedOpen: true))
        settings.settings.glassTint = AppSettings.default.glassTint

        settings.settings.islandMaterial = .black
        render("08-expanded-classic-black", IslandInputs(isPinnedOpen: true))
        settings.settings.islandMaterial = .liquidGlass

        island.forceDragKind(.file)
        island.isDropTargeted = true
        render("09-expanded-drop-target", IslandInputs(isFileDragNearby: true))
        island.isDropTargeted = false
        island.forceDragKind(.none)

        music.preview(track: nil, state: .stopped, artwork: nil, elapsed: 0)
        shelf.clear()
        weather.preview(nil)
        render("10-expanded-empty-states", IslandInputs(isPinnedOpen: true))

        settings.settings.notchLeading = .weather
        settings.settings.notchTrailing = .time
        render("12-compact-notch-info", IslandInputs(showsInfo: true), height: 120)
        settings.settings.notchLeading = .battery
        settings.settings.notchTrailing = .date
        render("13-compact-notch-battery-date", IslandInputs(showsInfo: true), height: 120)
        settings.settings.notchLeading = .none
        settings.settings.notchTrailing = .none

        music.preview(track: DemoContent.track, state: .playing, artwork: DemoContent.artwork(), elapsed: 170)
        render("14-edit-mode", IslandInputs(isEditing: true))
        island.forceInputs(IslandInputs())

        island.forceDragKind(.link)
        island.isDropTargeted = true
        render("15-link-drop", IslandInputs(isFileDragNearby: true))
        island.isDropTargeted = false
        island.forceDragKind(.none)

        settings.settings.widgets = [
            WidgetConfig(kind: .weather, isEnabled: true),
            WidgetConfig(kind: .webPages, isEnabled: true),
            WidgetConfig(kind: .nowPlaying, isEnabled: false),
            WidgetConfig(kind: .fileShelf, isEnabled: false)
        ]
        weather.preview(DemoContent.weather)
        render("11-expanded-two-widgets", IslandInputs(isPinnedOpen: true))

        return failures == 0 ? 0 : 1
    }

    private static func spin(until condition: () -> Bool, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}

/// A slice of a MacBook screen: wallpaper, menu bar and hardware notch, with the island on top.
struct SnapshotScene: View {
    let model: IslandViewModel
    let canvas: CGSize

    var body: some View {
        let notch = model.notch.size
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(red: 0.84, green: 0.56, blue: 0.93),
                    Color(red: 0.55, green: 0.25, blue: 0.85),
                    Color(red: 0.2, green: 0.07, blue: 0.45),
                    Color(red: 0.05, green: 0.02, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: 18) {
                Image(systemName: "apple.logo")
                Text("Finder").fontWeight(.bold)
                Text("File")
                Text("Edit")
                Text("View")
                Text("Go")
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text("Thu Oct 30  9:41 AM")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: notch.height)

            NotchShape(topRadius: 6, bottomRadius: 10)
                .fill(Color.black)
                .frame(width: notch.width + 12, height: notch.height)

            IslandRootView(model: model)
        }
        .frame(width: canvas.width, height: canvas.height)
        .environment(\.colorScheme, .dark)
    }
}

import XCTest
@testable import NotchCore

final class MusicTests: XCTestCase {
    func testParsesPlayingNotification() {
        let info: [AnyHashable: Any] = [
            "Player State": "Playing",
            "Name": "Entropy",
            "Artist": "Beach Bunny",
            "Album": "Emotional Creature",
            "Total Time": NSNumber(value: 221_000)
        ]
        let parsed = MusicPlayerInfoParser.parse(info)
        XCTAssertEqual(parsed.state, .playing)
        XCTAssertEqual(parsed.track, TrackInfo(title: "Entropy", artist: "Beach Bunny", album: "Emotional Creature", duration: 221))
    }

    func testParsesPausedWithIntegerDuration() {
        let info: [AnyHashable: Any] = ["Player State": "Paused", "Name": "Song", "Total Time": 90_500]
        let parsed = MusicPlayerInfoParser.parse(info)
        XCTAssertEqual(parsed.state, .paused)
        XCTAssertEqual(parsed.track?.duration ?? 0, 90.5, accuracy: 0.001)
        XCTAssertEqual(parsed.track?.artist, "")
    }

    func testStoppedHasNoTrack() {
        let parsed = MusicPlayerInfoParser.parse(["Player State": "Stopped", "Name": "Leftover"])
        XCTAssertEqual(parsed.state, .stopped)
        XCTAssertNil(parsed.track)
        XCTAssertEqual(MusicPlayerInfoParser.parse([:]).state, .stopped)
    }

    func testRadioStreamWithoutDuration() {
        let parsed = MusicPlayerInfoParser.parse(["Player State": "Playing", "Stream Title": "Apple Music 1"])
        XCTAssertEqual(parsed.track?.artist, "Apple Music 1")
        XCTAssertEqual(parsed.track?.title, "Unknown Title")
        XCTAssertEqual(parsed.track?.duration, 0)
    }

    func testPositionExtrapolatesOnlyWhilePlaying() {
        let start = Date(timeIntervalSince1970: 100)
        let playing = PlaybackPosition(elapsed: 10, timestamp: start, isPlaying: true)
        XCTAssertEqual(playing.elapsed(at: start.addingTimeInterval(5), duration: 200), 15, accuracy: 0.001)
        XCTAssertEqual(playing.elapsed(at: start.addingTimeInterval(500), duration: 200), 200, accuracy: 0.001)
        XCTAssertEqual(playing.progress(at: start.addingTimeInterval(90), duration: 200), 0.5, accuracy: 0.001)
        XCTAssertEqual(playing.elapsed(at: start.addingTimeInterval(-50), duration: 200), 10, accuracy: 0.001)

        let paused = PlaybackPosition(elapsed: 10, timestamp: start, isPlaying: false)
        XCTAssertEqual(paused.elapsed(at: start.addingTimeInterval(60), duration: 200), 10, accuracy: 0.001)
        XCTAssertEqual(paused.progress(at: start, duration: 0), 0)
    }

    func testClockFormatting() {
        XCTAssertEqual(TimeFormatting.clock(0), "0:00")
        XCTAssertEqual(TimeFormatting.clock(5.9), "0:05")
        XCTAssertEqual(TimeFormatting.clock(221), "3:41")
        XCTAssertEqual(TimeFormatting.clock(3729), "1:02:09")
        XCTAssertEqual(TimeFormatting.clock(-4), "0:00")
        XCTAssertEqual(TimeFormatting.clock(.nan), "0:00")
        XCTAssertEqual(TimeFormatting.remaining(elapsed: 170, duration: 221), "-0:51")
        XCTAssertEqual(TimeFormatting.remaining(elapsed: 300, duration: 221), "-0:00")
    }
}

final class ShelfTests: XCTestCase {
    func testAddDeduplicatesAndKeepsNewestFirst() {
        var shelf = ShelfStore()
        let a = URL(fileURLWithPath: "/tmp/a.png")
        let b = URL(fileURLWithPath: "/tmp/b.pdf")
        XCTAssertEqual(shelf.add([a, b]), 2)
        XCTAssertEqual(shelf.add([a, URL(fileURLWithPath: "/tmp/./a.png")]), 0)
        XCTAssertEqual(shelf.items.map(\.displayName), ["b.pdf", "a.png"])
    }

    func testIgnoresNonFileURLs() {
        var shelf = ShelfStore()
        XCTAssertEqual(shelf.add([URL(string: "https://example.com/file.zip")!]), 0)
        XCTAssertTrue(shelf.items.isEmpty)
    }

    func testRemoveAndClear() {
        var shelf = ShelfStore()
        shelf.add([URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")])
        let first = shelf.items[0]
        shelf.remove(id: first.id)
        XCTAssertEqual(shelf.items.count, 1)
        XCTAssertFalse(shelf.items.contains(first))
        shelf.removeAll()
        XCTAssertTrue(shelf.items.isEmpty)
    }

    func testCapsItemCount() {
        var shelf = ShelfStore()
        let urls = (0..<(ShelfStore.maxItems + 10)).map { URL(fileURLWithPath: "/tmp/file\($0)") }
        shelf.add(urls)
        XCTAssertEqual(shelf.items.count, ShelfStore.maxItems)
        XCTAssertEqual(shelf.items.first?.displayName, "file\(ShelfStore.maxItems + 9)")
    }

    func testPruneMissing() {
        var shelf = ShelfStore()
        shelf.add([URL(fileURLWithPath: "/tmp/keep"), URL(fileURLWithPath: "/tmp/gone")])
        shelf.pruneMissing { $0.hasSuffix("keep") }
        XCTAssertEqual(shelf.items.map(\.displayName), ["keep"])
    }

    func testCodableRoundTrip() throws {
        var shelf = ShelfStore()
        shelf.add([URL(fileURLWithPath: "/Users/jonah/Desktop/Thumbnail.png")])
        let decoded = try JSONDecoder().decode(ShelfStore.self, from: JSONEncoder().encode(shelf))
        XCTAssertEqual(decoded, shelf)
    }
}

final class ColorMathTests: XCTestCase {
    func testHSBRoundTrip() {
        let colors = [
            RGB(red: 1, green: 0, blue: 0), RGB(red: 0.2, green: 0.6, blue: 0.3),
            RGB(red: 0.1, green: 0.2, blue: 0.9), RGB(red: 0.5, green: 0.5, blue: 0.5),
            RGB(red: 0.9, green: 0.1, blue: 0.7)
        ]
        for color in colors {
            let back = ColorMath.rgb(from: ColorMath.hsb(from: color))
            XCTAssertEqual(back.red, color.red, accuracy: 0.0001)
            XCTAssertEqual(back.green, color.green, accuracy: 0.0001)
            XCTAssertEqual(back.blue, color.blue, accuracy: 0.0001)
        }
    }

    func testVibrantAccentBrightensDarkColors() {
        let accent = ColorMath.vibrantAccent(from: RGB(red: 0.3, green: 0.05, blue: 0.05))
        let hsb = ColorMath.hsb(from: accent)
        XCTAssertGreaterThanOrEqual(hsb.brightness, 0.72)
        XCTAssertGreaterThan(hsb.saturation, 0.8)
        XCTAssertLessThan(hsb.hue, 0.05)
    }

    func testGrayArtworkGivesSoftWhite() {
        let accent = ColorMath.vibrantAccent(from: RGB(red: 0.4, green: 0.41, blue: 0.4))
        XCTAssertGreaterThan(accent.red, 0.9)
        XCTAssertGreaterThan(accent.blue, 0.9)
    }
}

import AppKit
import NotchUI

MainActor.assumeIsolated {
    let arguments = CommandLine.arguments

    // CI: render every island state to PNG files and exit.
    if let index = arguments.firstIndex(of: "--render-snapshots") {
        let path = index + 1 < arguments.count ? arguments[index + 1] : "snapshots"
        _ = NSApplication.shared
        exit(SnapshotRenderer.renderAll(to: URL(fileURLWithPath: path)))
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

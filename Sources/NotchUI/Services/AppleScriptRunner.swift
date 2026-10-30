import Foundation

/// Runs AppleScript off the main thread, one script at a time.
final class AppleScriptRunner: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case notPermitted
        case appNotRunning
        case other(Int)
    }

    /// Plain values pulled out of an NSAppleEventDescriptor so they can cross threads.
    struct Output: Sendable {
        var strings: [String]
        var numbers: [Double]
        var data: Data?
    }

    private let queue = DispatchQueue(label: "app.macnotch.applescript", qos: .userInitiated)

    func run(_ source: String) async -> Result<Output, Failure> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.execute(source))
            }
        }
    }

    private static func execute(_ source: String) -> Result<Output, Failure> {
        guard let script = NSAppleScript(source: source) else { return .failure(.other(-1)) }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
            switch code {
            case -1743, -1744: return .failure(.notPermitted)
            case -600, -609: return .failure(.appNotRunning)
            default: return .failure(.other(code))
            }
        }
        return .success(output(from: descriptor))
    }

    private static func output(from descriptor: NSAppleEventDescriptor) -> Output {
        var strings: [String] = []
        var numbers: [Double] = []
        let count = descriptor.numberOfItems
        if count > 0 {
            for index in 1...count {
                guard let item = descriptor.atIndex(index) else {
                    strings.append("")
                    numbers.append(0)
                    continue
                }
                strings.append(item.stringValue ?? "")
                numbers.append(item.doubleValue)
            }
        } else {
            strings.append(descriptor.stringValue ?? "")
            numbers.append(descriptor.doubleValue)
        }
        let data = descriptor.data
        return Output(strings: strings, numbers: numbers, data: data.isEmpty ? nil : data)
    }
}

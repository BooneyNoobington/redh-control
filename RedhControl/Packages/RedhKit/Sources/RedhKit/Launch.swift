import Foundation

/// Launch arguments, for trying the apps and for screenshots: `-demo` shows the demo homelab. The
/// iPhone app also takes `-open NAME`, `-open NAME -edit` and `-open setup`.
public enum LaunchOptions {
    public static func has(_ flag: String, in arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(flag)
    }

    public static func value(after flag: String, in arguments: [String] = CommandLine.arguments) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}

extension Monitor {
    /// What an app starts with: the demo with `-demo`, otherwise the saved setup and the Keychain.
    public static func forLaunch(arguments: [String] = CommandLine.arguments) throws -> Monitor {
        LaunchOptions.has("-demo", in: arguments) ? Demo.monitor() : try standard()
    }
}

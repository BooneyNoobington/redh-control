import Foundation

/// The color family of a reading; the apps turn it into a color.
public enum Tone: Hashable, Sendable {
    case up, caution, down, unknown, busy
}

extension Reading {
    /// The state in two or three words.
    public var title: String {
        switch state {
        case .up: "Up"
        case .upWithoutStatus: "Up, no status"
        case .probablyUp: "Probably up"
        case .probablyDown: "Probably down"
        case .unknown: "Unknown"
        case .waking: "Waking up"
        case .shuttingDown: "Shutting down"
        }
    }

    public var symbolName: String {
        switch state {
        case .up: "checkmark.circle.fill"
        case .upWithoutStatus, .probablyUp: "exclamationmark.circle.fill"
        case .probablyDown: "moon.zzz.fill"
        case .unknown: "questionmark.circle.fill"
        case .waking: "sunrise.fill"
        case .shuttingDown: "power.circle.fill"
        }
    }

    public var tone: Tone {
        switch state {
        case .up: .up
        case .upWithoutStatus, .probablyUp: .caution
        case .probablyDown: .down
        case .unknown: .unknown
        case .waking, .shuttingDown: .busy
        }
    }

    /// One line under the server's name: how long it has been running, or what the guess is
    /// based on.
    public var summary: String {
        if let detail {
            return detail
        }
        switch state {
        case .up(let status):
            return status.uptimeSeconds.map { "Running for \(uptimeText($0))" } ?? "Running"
        case .upWithoutStatus: return "RedhAPI gives no status."
        case .probablyUp: return "The FRITZ!Box sees it, but RedhAPI doesn't answer."
        case .probablyDown: return "Neither RedhAPI nor the FRITZ!Box sees it."
        case .unknown: return "RedhAPI doesn't answer, and the FRITZ!Box can't say."
        case .waking: return "Woken up; waiting for RedhAPI to answer."
        case .shuttingDown: return "The shutdown was accepted; waiting for it to go."
        }
    }
}

extension Reading {
    /// The wake command's name: "Wake Up Again" while a wake-up is under way.
    public var wakeTitle: String {
        state == .waking ? "Wake Up Again" : "Wake Up"
    }
}

extension WakeCheck {
    /// What to say before an always-on server is shut down.
    public var explanation: String {
        switch self {
        case .possible(let how): how
        case .uncertain(let why): "\(why) It would have to be switched on by hand."
        }
    }
}

extension Setup {
    /// What the question before a shutdown says. For a rooster, the warning that nothing else can
    /// wake its servers while it's off; for any other server, what can wake it up again.
    public func shutdownNote(for server: Server) -> String {
        let woken = servers(wokenBy: server).map(\.name)
        let box = box(for: server)?.name
        let rooster = roosterServer(for: server)?.name
        if !woken.isEmpty {
            let only = "Only \(server.name) can wake \(listed(woken)) up"
            guard server.mac != nil, let waker = box.map({ "the FRITZ!Box \($0)" }) ?? rooster else {
                return "\(only), and nothing can wake \(server.name) up again."
            }
            return "\(only). Afterwards, \(waker) has to wake \(server.name) first."
        }
        if box == nil, rooster == nil {
            return "It has no rooster, so nothing can wake it up again."
        }
        if server.mac == nil {
            return "Without its MAC address, nothing can wake it up again."
        }
        if let box {
            return "Its FRITZ!Box \(box) can wake it up again."
        }
        return "Its rooster \(rooster ?? "") can wake it up again."
    }
}

/// "nas", "nas and media", "nas, media and backup".
func listed(_ names: [String]) -> String {
    guard let last = names.last, names.count > 1 else { return names.first ?? "" }
    return names.dropLast().joined(separator: ", ") + " and " + last
}

/// "12 days", "1 hour", "5 minutes": the largest unit only.
public func uptimeText(_ seconds: Int) -> String {
    let units: [(seconds: Int, name: String)] = [(86_400, "day"), (3_600, "hour"), (60, "minute")]
    for unit in units where seconds >= unit.seconds {
        let count = seconds / unit.seconds
        return "\(count) \(unit.name)\(count == 1 ? "" : "s")"
    }
    return "less than a minute"
}

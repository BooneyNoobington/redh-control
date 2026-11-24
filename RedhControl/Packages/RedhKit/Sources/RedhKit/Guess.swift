import Foundation

/// What RedhAPI said, or why it said nothing.
public enum APIAnswer: Hashable, Sendable {
    /// The status: the server is up.
    case status(ServerStatus)
    /// RedhAPI answered, but without the status: there's no token, or it isn't accepted.
    case noAccess(String)
    /// Caddy answered for RedhAPI: the server is up, RedhAPI isn't running.
    case notRunning
    /// RedhAPI answered with an error, so the server is up.
    case failed(String)
    /// No answer: the server is down, or can't be reached.
    case unreachable(String)
    /// The certificate was refused, so the answer couldn't be trusted.
    case untrusted(String)
}

/// What the server's rooster said while the server's RedhAPI didn't answer.
public enum RoosterAnswer: Hashable, Sendable {
    /// The FRITZ!Box sees the server on the network.
    case active
    /// The FRITZ!Box knows the server, but doesn't see it.
    case inactive
    /// The FRITZ!Box doesn't know the server's MAC address at all.
    case unknownHost
    /// The rooster, another server, answers: the homelab can be reached, so the server is
    /// probably down. The text is the rooster's name.
    case answers(String)
    /// It couldn't be asked: none in the setup, unreachable, login refused.
    case unavailable(String)
    /// It wasn't asked: RedhAPI answered, or the server has no rooster to ask.
    case notAsked
}

/// A command whose effect hasn't shown yet.
public enum PendingCommand: Hashable, Sendable {
    case wake(since: Date)
    case shutdown(since: Date)
}

/// The best guess about a server.
public enum ServerState: Hashable, Sendable {
    case up(ServerStatus)
    /// Up, but without a status from RedhAPI; the detail says why.
    case upWithoutStatus
    /// RedhAPI doesn't answer, but the box sees the server.
    case probablyUp
    /// Neither RedhAPI nor the box sees the server.
    case probablyDown
    /// RedhAPI doesn't answer, and the box can't say.
    case unknown
    /// Woken up, not up yet.
    case waking
    /// The shutdown was accepted, the server isn't down yet.
    case shuttingDown
}

/// A guess, with what's behind it.
public struct Reading: Hashable, Sendable {
    public var state: ServerState
    /// Why, in a sentence, when there's more to it than the state.
    public var detail: String?
    /// The command still waiting for its effect; nil once it showed, or failed to show in time.
    public var command: PendingCommand?

    public init(state: ServerState, detail: String? = nil, command: PendingCommand? = nil) {
        self.state = state
        self.detail = detail
        self.command = command
    }

    /// Whether RedhAPI answered with the status.
    public var isUp: Bool {
        if case .up = state {
            return true
        }
        return false
    }

    /// Whether RedhAPI answered, with the status or without; a rooster server can wake others
    /// only then.
    public var answers: Bool {
        switch state {
        case .up, .upWithoutStatus: true
        case .probablyUp, .probablyDown, .unknown, .waking, .shuttingDown: false
        }
    }

    /// Whether shutting the server down makes sense now.
    public var canShutDown: Bool {
        guard command == nil, case .up(let status) = state else { return false }
        return status.shutdown.ready
    }

    /// Whether waking the server up makes sense now. Waking a server that is up does no harm,
    /// so "probably up" allows it too. So does a wake-up under way: its packet may have got lost.
    public var canWake: Bool {
        switch state {
        case .waking: return true
        case .probablyUp, .probablyDown, .unknown: return command == nil
        case .up, .upWithoutStatus, .shuttingDown: return false
        }
    }
}

/// From what RedhAPI and the rooster said, and the command waiting, to a ``Reading``.
public enum Guess {
    /// How long a woken server may take to answer.
    public static let wakeTimeout: TimeInterval = 300
    /// How long a server may take to go away once it accepted the shutdown.
    public static let shutdownTimeout: TimeInterval = 180

    public static func reading(api: APIAnswer, rooster: RoosterAnswer, command: PendingCommand?, now: Date) -> Reading {
        let reading = plain(api: api, rooster: rooster)
        switch command {
        case nil:
            return reading
        case .wake(let since)?:
            return waking(reading, since: since, now: now)
        case .shutdown(let since)?:
            return shuttingDown(reading, since: since, now: now)
        }
    }

    /// The guess without a command.
    static func plain(api: APIAnswer, rooster: RoosterAnswer) -> Reading {
        let reason: String
        switch api {
        case .status(let status): return Reading(state: .up(status))
        case .noAccess(let why): return Reading(state: .upWithoutStatus, detail: why)
        case .notRunning: return Reading(state: .upWithoutStatus, detail: "RedhAPI isn't running.")
        case .failed(let why): return Reading(state: .upWithoutStatus, detail: why)
        case .unreachable(let why): reason = "RedhAPI doesn't answer: \(why)"
        case .untrusted(let why): reason = "RedhAPI's certificate was refused: \(why)"
        }
        let certificate: String? = if case .untrusted = api { reason } else { nil }
        switch rooster {
        case .active: return Reading(state: .probablyUp, detail: reason)
        case .inactive: return Reading(state: .probablyDown, detail: certificate)
        case .unknownHost: return Reading(state: .unknown, detail: "The FRITZ!Box doesn't know its MAC address.")
        case .answers(let name):
            return Reading(state: .probablyDown, detail: certificate ?? "RedhAPI doesn't answer, while its rooster \(name) does.")
        case .unavailable(let why): return Reading(state: .unknown, detail: why)
        case .notAsked: return Reading(state: .unknown, detail: reason)
        }
    }

    static func waking(_ reading: Reading, since: Date, now: Date) -> Reading {
        switch reading.state {
        case .up, .upWithoutStatus:
            return reading
        default:
            if now.timeIntervalSince(since) < wakeTimeout {
                return Reading(state: .waking, command: .wake(since: since))
            }
            var late = reading
            late.detail = "It didn't come up within \(minutes(wakeTimeout)) minutes."
            return late
        }
    }

    static func shuttingDown(_ reading: Reading, since: Date, now: Date) -> Reading {
        let inTime = now.timeIntervalSince(since) < shutdownTimeout
        switch reading.state {
        case .up(let status):
            if let error = status.shutdown.lastError, !status.shutdown.pending {
                return Reading(state: reading.state, detail: "The shutdown failed: \(error)")
            }
            fallthrough
        case .upWithoutStatus:
            if inTime {
                return Reading(state: .shuttingDown, command: .shutdown(since: since))
            }
            return Reading(state: reading.state,
                           detail: "It's still up \(minutes(shutdownTimeout)) minutes after the shutdown request.")
        case .probablyUp, .unknown:
            // RedhAPI took the request and went away. The box may not have noticed yet.
            if inTime {
                return Reading(state: .shuttingDown, command: .shutdown(since: since))
            }
            let note = reading.state == .probablyUp ? "The FRITZ!Box still counts it as active." : reading.detail
            return Reading(state: .probablyDown, detail: note)
        case .probablyDown, .waking, .shuttingDown:
            return reading
        }
    }

    private static func minutes(_ seconds: TimeInterval) -> Int {
        Int(seconds / 60)
    }
}

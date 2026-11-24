import Foundation
import Testing
@testable import RedhKit

struct GuessTests {
    let ready = ServerStatus(name: "lab", version: "0.1.0", shutdown: ShutdownStatus(ready: true))
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func reading(_ api: APIAnswer, _ rooster: RoosterAnswer = .notAsked, command: PendingCommand? = nil,
                 after seconds: TimeInterval = 0) -> Reading {
        Guess.reading(api: api, rooster: rooster, command: command, now: start.addingTimeInterval(seconds))
    }

    @Test func anAnswerFromRedhAPIMeansUp() {
        #expect(reading(.status(ready)) == Reading(state: .up(ready)))
        #expect(reading(.noAccess("There's no token for lab."))
                == Reading(state: .upWithoutStatus, detail: "There's no token for lab."))
        #expect(reading(.notRunning) == Reading(state: .upWithoutStatus, detail: "RedhAPI isn't running."))
        #expect(reading(.failed("RedhAPI answered with HTTP 500: boom"))
                == Reading(state: .upWithoutStatus, detail: "RedhAPI answered with HTTP 500: boom"))
    }

    @Test func withoutRedhAPITheBoxDecides() {
        let silent = APIAnswer.unreachable("timed out")
        #expect(reading(silent, .active) == Reading(state: .probablyUp, detail: "RedhAPI doesn't answer: timed out"))
        #expect(reading(silent, .inactive) == Reading(state: .probablyDown))
        #expect(reading(silent, .unknownHost)
                == Reading(state: .unknown, detail: "The FRITZ!Box doesn't know its MAC address."))
        #expect(reading(silent, .unavailable("There's no password.")) == Reading(state: .unknown, detail: "There's no password."))
    }

    @Test func aRoosterServerThatAnswersMeansProbablyDown() {
        #expect(reading(.unreachable("timed out"), .answers("nas"))
                == Reading(state: .probablyDown, detail: "RedhAPI doesn't answer, while its rooster nas does."))
    }

    @Test func withNothingToAskItsUnknown() {
        #expect(reading(.unreachable("timed out")) == Reading(state: .unknown, detail: "RedhAPI doesn't answer: timed out"))
    }

    @Test func aRoosterAnswersOnlyWhenRedhAPIDoesnt() {
        let status = ServerStatus(name: "lab", version: "0.2.0", shutdown: ShutdownStatus(ready: true))
        #expect(Reading(state: .up(status)).answers)
        #expect(Reading(state: .upWithoutStatus).answers)
        for state in [ServerState.probablyUp, .probablyDown, .unknown, .waking, .shuttingDown] {
            #expect(!Reading(state: state).answers)
        }
    }

    @Test func aRefusedCertificateIsAlwaysMentioned() {
        #expect(reading(.untrusted("another root"), .inactive)
                == Reading(state: .probablyDown, detail: "RedhAPI's certificate was refused: another root"))
    }

    @Test func whatMakesSense() {
        var notReady = ready
        notReady.shutdown = ShutdownStatus(ready: false, problem: "/usr/local/bin/redh-shut does not exist")
        #expect(reading(.status(ready)).canShutDown)
        #expect(!reading(.status(notReady)).canShutDown)
        #expect(reading(.status(notReady)).isUp)
        #expect(!reading(.notRunning).isUp)
        #expect(!reading(.status(ready)).canWake)
        #expect(!reading(.notRunning).canWake)
        #expect(reading(.unreachable("timed out"), .inactive).canWake)
        #expect(reading(.unreachable("timed out"), .active).canWake)
        // Again while a wake-up is under way, but no more once RedhAPI answers.
        #expect(reading(.unreachable("timed out"), .inactive, command: .wake(since: start)).canWake)
        #expect(!reading(.status(ready), command: .wake(since: start)).canWake)
    }

    @Test func wakingUntilItAnswers() {
        let wake = PendingCommand.wake(since: start)
        let waking = Reading(state: .waking, command: wake)
        #expect(reading(.unreachable("timed out"), .inactive, command: wake, after: 60) == waking)
        #expect(reading(.unreachable("timed out"), .active, command: wake, after: 60) == waking)
        #expect(reading(.status(ready), command: wake, after: 60) == Reading(state: .up(ready)))
        #expect(reading(.notRunning, command: wake, after: 60).command == nil)
    }

    @Test func wakingGivesUp() {
        #expect(reading(.unreachable("timed out"), .inactive, command: .wake(since: start), after: Guess.wakeTimeout)
                == Reading(state: .probablyDown, detail: "It didn't come up within 5 minutes."))
    }

    @Test func shuttingDownUntilItIsGone() {
        let shutdown = PendingCommand.shutdown(since: start)
        let shuttingDown = Reading(state: .shuttingDown, command: shutdown)
        #expect(reading(.status(ready), command: shutdown, after: 1) == shuttingDown)
        #expect(reading(.notRunning, command: shutdown, after: 10) == shuttingDown)
        #expect(reading(.unreachable("timed out"), .active, command: shutdown, after: 30) == shuttingDown)
        #expect(reading(.unreachable("timed out"), .inactive, command: shutdown, after: 30) == Reading(state: .probablyDown))
        #expect(!reading(.status(ready), command: shutdown, after: 1).canShutDown)
    }

    @Test func aFailedShutdownShows() {
        var failed = ready
        failed.shutdown.lastError = "/usr/local/bin/redh-shut failed with exit status 3: disk busy"
        #expect(reading(.status(failed), command: .shutdown(since: start), after: 5)
                == Reading(state: .up(failed),
                           detail: "The shutdown failed: /usr/local/bin/redh-shut failed with exit status 3: disk busy"))
    }

    @Test func shuttingDownGivesUp() {
        let shutdown = PendingCommand.shutdown(since: start)
        #expect(reading(.status(ready), command: shutdown, after: Guess.shutdownTimeout)
                == Reading(state: .up(ready), detail: "It's still up 3 minutes after the shutdown request."))
        #expect(reading(.unreachable("timed out"), .active, command: shutdown, after: Guess.shutdownTimeout)
                == Reading(state: .probablyDown, detail: "The FRITZ!Box still counts it as active."))
    }
}

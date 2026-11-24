# RedhKit

The code the apps of Redh Control share, for iPhone, Apple Watch and Mac, with no dependencies.
`RedhKit` uses only Foundation, Security, CryptoKit and Observation; `RedhUI` adds the views they
show, in SwiftUI. The tests run on macOS with `swift test`. Both build for iOS 17, watchOS 10 and
macOS 14.

| File | What it does |
|---|---|
| `Setup.swift` | The setup: boxes, servers (with their rooster, icon, color and whether always on), the root certificate. No secrets. |
| `SetupFile.swift` | The setup as JSON in Application Support, in format 2; format 1, with a box per server, is still read |
| `Secrets.swift` | Tokens and FRITZ!Box passwords: in the Keychain, on this device only (on the Mac, the login keychain); in memory for tests |
| `MACAddress.swift` | MAC addresses, read in the usual spellings, written as the FRITZ!Box wants them |
| `Trust.swift` | Certificate pins, pairing codes, and the two trust policies: a root CA for RedhAPI behind Caddy, a pinned certificate for a FRITZ!Box or for RedhAPI's own |
| `Transport.swift` | URLSession with those policies. A refusal names the certificate the server presented. |
| `RedhAPIClient.swift` | `/health`, `/v1/status`, `/v1/shutdown`, `/v1/apps`, `/v1/system` and `/v1/wake`, as RedhAPI's README (repository `redh-api`) describes them |
| `SystemReport.swift` | What `/v1/system` answers: the machine's processor, temperature, power, memory and disks, and the lines of the System section |
| `Apps.swift` | What `/v1/apps` answers: redh-manager's list of a server's apps, and lines about it as redh's table has them |
| `Digest.swift`, `SOAP.swift`, `FritzBoxClient.swift` | TR-064 on the FRITZ!Box: Wake-on-LAN and the host list, behind a Digest login |
| `Guess.swift` | From the answers of RedhAPI and the rooster to up, down, waking and shutting down |
| `Homelab.swift` | All of it together: `probe`, `wake` through the server's rooster, `shutDown`, and `wakeCheck` before an always-on server is shut down |
| `Monitor.swift` | What the apps show: the setup, a reading per server, the commands waiting; changes saved at once |
| `Presentation.swift` | A reading in words, as an SF Symbol and a tone; what the question before a shutdown says, with the warning for a rooster |
| `RootCertificate.swift` | The CA's root certificate from PEM or DER |
| `Demo.swift` | A made-up homelab for previews, screenshots, `-demo` and Try the Demo, without any network |
| `Launch.swift` | The launch arguments, and the monitor an app starts with |
| `WatchSync.swift` | What the iPhone sends the Watch: the setup and its secrets, and putting them into place |
| `WatchLink.swift` | WatchConnectivity: the iPhone sends whenever the setup changes, the Watch takes the latest. iOS and watchOS only, so `swift test` doesn't build it. |
| `RedhUI/Views.swift` | The server's icon tile, the state as a line or as a badge, the colors |
| `RedhUI/Modifiers.swift` | Looking at the servers while the app is in front, and the error alert |
| `RedhUI/ServerDetail.swift`, `SystemSection.swift`, `AppsSection.swift` | A server's page for the iPhone and the Mac: its state, the commands, RedhAPI's status, and every 10 seconds while it's up what its machine is doing and its apps |
| `RedhUI/SetupView.swift`, `BoxEditor.swift`, `ServerEditor.swift`, `IconPicker.swift`, `Fields.swift` | The setup for the iPhone and the Mac; the Watch gets its setup from the iPhone |

## How a server is judged

`Homelab.probe` asks RedhAPI first: for the status with a token, for `/health` without one. Only
when RedhAPI doesn't answer does it ask the FRITZ!Box whether it sees the server's MAC address.
`Guess` turns the answers into a `Reading`:

| RedhAPI | FRITZ!Box | Reading |
|---|---|---|
| the status | not asked | up |
| no token, a 401, a 502 from Caddy, an error | not asked | up, without a status |
| no answer | sees the server | probably up |
| no answer | doesn't see it | probably down |
| no answer | can't say | unknown |

After a wake-up, the reading is "waking" until RedhAPI answers, for 5 minutes at most. Waking it
again meanwhile sends the packet once more and starts the 5 minutes anew, in case the first one got
lost. After a shutdown, it is "shutting down" until the server is gone, for 3 minutes at most. A
failed shutdown shows at once, from `last_error` in RedhAPI's status.

Before an always-on server is shut down, `Homelab.wakeCheck` asks its FRITZ!Box whether it knows the
server's MAC address: if it does, it can wake the server up again. Without a box, a MAC address or a
password, or when the box can't be asked, the answer is uncertain, and says why.

## Trust

No policy accepts any certificate:
- **RedhAPI:** its certificate has to be issued by the setup's root certificate, the homelab's
  ACME CA, and by no other root, for the host name asked for.
- **A FRITZ!Box:** its self-signed certificate is pinned by its SHA-256. Until then, every
  connection to the box is refused. The refusal names the certificate the box presented
  (`Homelab.presentedCertificate(of:)`), so the app can show it for confirmation, like a new
  SSH host key.

## Tests

```sh
cd RedhControl/Packages/RedhKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

- The trust tests use real certificates from `Tests/RedhKitTests/Fixtures`, which
  `make-certificates.sh` there makes.
- The digest tests use the example of RFC 2617, and answers computed with Python's hashlib.
- `keychainOnTheMac` stores, reads and removes an item of its own in your login keychain, under
  the service `com.redhwire.redhcontrol.tests`. Like the Mac app, the test has no keychain access
  group, so it fails if the store ever needs one.
- The client decodes copies of the examples in RedhAPI's README, `Fixtures/status.json`,
  `apps.json` and `system.json`. Where RedhAPI is checked out next to this repository, as
  `../redh-api` or `../redhapi`, `ContractTests` compares the copies with the README, so the two
  can't drift apart unnoticed.
- The TR-064 answers in the fixtures follow AVM's documentation of the Hosts service; they
  weren't captured from a box. The apps work with a real one, though: its host list gives
  "Probably up" and "Probably down" on the iPhone and on the Watch.

`LiveTransportTests` try `URLSessionTransport` against a real TLS server that answers `/health`,
such as RedhAPI behind Caddy. They are skipped unless two variables say where, the second one
naming the CA's root certificate in DER:

```sh
openssl x509 -in root.crt -outform DER -out /tmp/root.der
REDHKIT_LIVE_URL=https://rapi.SERVER.internal REDHKIT_LIVE_ROOT=/tmp/root.der \
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter LiveTransportTests
```

They have passed against a local HTTPS server with a certificate for `localhost` from a throwaway
root, and against RedhAPI behind Caddy: on macOS, and in the iOS and watchOS 27.2 simulators, which
don't have the homelab's CA in their trust stores. In a simulator, `TEST_RUNNER_` hands the
variables to the tests, and the package's scheme finds the simulator only by its ID
(`xcrun simctl list devices available`):

```sh
TEST_RUNNER_REDHKIT_LIVE_URL=https://rapi.SERVER.internal TEST_RUNNER_REDHKIT_LIVE_ROOT=/tmp/root.der \
    xcodebuild test -scheme RedhKit-Package -destination 'id=SIMULATOR-ID' \
    -only-testing:RedhKitTests/LiveTransportTests
```

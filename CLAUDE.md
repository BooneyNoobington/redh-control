# Redh Control: orientation for Claude sessions

Redh Control shuts down, wakes up and keeps an eye on the homelab's servers, from an iPhone, an
Apple Watch and a Mac. [PROJECT.md](PROJECT.md) is the owner's description, [README.md](README.md)
the overview. It's public on GitHub, `BooneyNoobington/redh-control`, under GPL-3.0-only, as are
`redh-api` and `redh-manager`; the owner's internal git server stays the remote of the checkouts.

| Directory | What | Reference |
|---|---|---|
| `RedhControl/Packages/RedhKit/` | Swift package the apps share: setup, Keychain, TLS trust, RedhAPI and TR-064 clients, the up/down guess | [its README](RedhControl/Packages/RedhKit/README.md) |
| `RedhControl/` | Xcode project: the iPhone app with the Watch app embedded, and the Mac app | [RedhControl/README.md](RedhControl/README.md) |

RedhAPI, the service on every server, is a repository of its own, `redh-api` on GitHub, with its
own CLAUDE.md. On the MacBook it is checked out next to this one, as `../redhapi`; a fresh clone
from GitHub would be `../redh-api`, which the contract tests find as well. Its README holds the
API contract.

## Ground rules

1. **Nothing real goes into the repository,** which is public: no host names, IP or MAC
   addresses, tokens, FRITZ!Box users or passwords. Use placeholders such as
   `rapi.SERVER.internal`. The real setup is entered in the app and on the servers.
2. **TLS is always verified:**
   - RedhAPI is reached through Caddy, with a certificate from the homelab's ACME CA, and the app
     trusts that CA's root explicitly.
   - Or RedhAPI serves HTTPS with a self-signed certificate of its own, and the app pins it per
     server from the pairing code of `redh-api token` (`PairingCode`, `Server.certificatePin`):
     the pin comes with the token, never from the network.
   - FRITZ!Boxes have self-signed certificates, which the app pins.
   - Never turn verification off, not even for a test. RedhKit's `TrustPolicy` has no case that
     accepts any certificate; keep it that way.
3. **The API contract is in RedhAPI's README.** The app follows it; change both together.
   RedhKit's tests decode copies of the status, apps and system examples
   (`Tests/RedhKitTests/Fixtures/`), and `ContractTests` compares them with RedhAPI's README
   wherever that is checked out next to this repository.
4. **The Swift code has no dependencies:** Foundation, Security, CryptoKit, SwiftUI and the like.
   No external packages.
5. **Every change comes complete:**
   - unit tests, green with `swift test`;
   - shell scripts clean under shellcheck;
   - the READMEs updated where they describe the change, with example output that comes from
     running the code.
6. **The owner deploys and pushes.** Claude doesn't touch the servers and never pushes.

## Commands (MacBook)

| | |
|---|---|
| `cd RedhControl/Packages/RedhKit && swift test` | RedhKit's tests on macOS |
| `xcodebuild -scheme RedhKit -destination 'generic/platform=watchOS' build`, in the package | RedhKit for watchOS (likewise iOS) |
| `xcodebuild -project RedhControl/RedhControl.xcodeproj -scheme RedhControl -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` | the iPhone app for devices, with the Watch app in it, without signing and without a simulator |
| `xcodebuild -project RedhControl/RedhControl.xcodeproj -scheme RedhControl -destination 'platform=iOS Simulator,name=iPhone 17' build` | the same for a simulator, when one is installed |
| `xcodebuild -project RedhControl/RedhControl.xcodeproj -scheme RedhControlWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build` | the Watch app for devices, without signing |
| `xcodebuild -project RedhControl/RedhControl.xcodeproj -scheme RedhControlMac -destination 'platform=macOS' -allowProvisioningUpdates build` | the Mac app, signed with the team from `Local.xcconfig` |
| `xcrun simctl launch booted com.redhwire.redhcontrol -demo -open nas` | the app with the demo homelab, on a server's page (more in RedhControl/README.md) |
| `xcrun simctl io booted screenshot shot.png` | a screenshot, to look at it |
| `xcrun devicectl list devices` | the real iPhone and Watch, and whether they're paired and reachable |
| `uvx --from shellcheck-py shellcheck RedhControl/Packages/RedhKit/Tests/RedhKitTests/Fixtures/make-certificates.sh` | shellcheck, which isn't installed |

`xcode-select` points to Xcode. On 2026-11-24 no simulator runtimes were installed (`xcrun simctl
list runtimes` was empty); Xcode > Settings > Components installs them. Before, they ran iOS 27.2
(iPhone 17, 17e and Air, iPads) and watchOS 27.2 (Apple Watch Ultra 4, SE 3 in 40 and 44 mm), and
Claude's iOS Simulator tool worked with both kinds: it taps, swipes and takes screenshots. For the
Watch app, build the RedhControlWatch scheme with
`-destination 'platform=watchOS Simulator,name=Apple Watch SE 3 (40mm)'`, the smallest watch, then
`xcrun simctl install` and `xcrun simctl launch <watch> com.redhwire.redhcontrol.watchkitapp -demo`.

The Apple developer account is a paid one since November 2026: the same team, with the same ID,
is no longer free. Development profiles last a year, and the App Store is open; [AppStore.md](AppStore.md)
has the listing.

## Lessons learned (don't repeat these)

- **URLSession** sends server-trust challenges to the session's delegate, so RedhKit keeps one
  session per `TrustPolicy`. The delegate records each refusal, so the caller learns which
  certificate the server presented.
- **Swift Testing:** a `@Suite` trait can't refer to its own suite type (a circular reference).
  Keep conditions such as `.enabled(if:)` in another type.
- **Test fixtures with `UUID()`:** a computed property that builds them makes new IDs on every
  access. Build them once, in `init()`.
- **The FRITZ!Box code** works with the real box: its host list gives "Probably up" and "Probably
  down" on the iPhone and the Watch. The fixtures still follow AVM's TR-064 documentation of the
  Hosts service, not captured answers.
- **Simulators come and go** with Xcode's updates: the iPhone Duo and the Series 11 and 12 watches
  of 1 November were gone a day later. Check `xcrun simctl list devices available` before naming
  one. The iPhone Duo had several displays, and `simctl io screenshot` needed `--display=primary`.
- **The package's scheme** (`RedhKit-Package`) finds simulators only by `id=`, not by name.
  Variables reach tests in a simulator with the prefix `TEST_RUNNER_`.
- **The real Watch** is reached over Wi-Fi only: Mac and Watch on the same network, not a guest
  network that keeps devices apart, no VPN on the Mac in between. Near its iPhone it may stay on
  Bluetooth. Developer Mode appears on the Watch once Xcode has seen it.
- **Xcode's destination menu** lists watch simulators named like real watches. "Mismatched
  platform" means scheme and destination don't fit: the iPhone scheme with a Watch, or the Watch
  scheme with an iPhone, which is also all Xcode offers while it doesn't see the Watch.
- **The first run on the Watch** mounts a developer disk image and timed out once ("Timed out
  while attempting to establish tunnel", RemotePairingError 1001). `devicectl device install app`
  and `process launch` put Xcode's build on the Watch directly; `devicectl device capture
  screenshot` shows its screen, and `device copy from` reads an app's container. `devicectl
  device process launch --console` passes on only the app's standard output, not its log.
- **The Watch and RedhAPI:** through the iPhone, the Watch's requests to RedhAPI fail with a
  system TLS error ("Aufgrund eines TLS-Fehlers…"), not with RedhKit's refusal, while the FRITZ!Box
  answers. In the watchOS simulator, RedhKit reaches the same RedhAPI over TCP and HTTP/3, without
  the CA in the trust store. The cause is still open; next step: show the error code behind it.
- **The signing team** lives in `RedhControl/Config/Local.xcconfig`, which git ignores. Xcode's
  Signing tab writes it into `project.pbxproj` instead: move it back before a commit.
- **On a 42 mm watch** a capsule with "Probably down" doesn't fit a row, so the Watch's rows use
  `StateLine`; check Watch layouts on the smallest simulator.
- **SwiftUI in lists:** a `Label` keeps a column free for its icon, which stretches small
  capsules; use an `HStack`. A disabled `Button` keeps its colored icon; color it explicitly.
- **The Xcode project** is hand-written, with synchronized folders (objectVersion 77): files
  added to `RedhControl/RedhControl/`, `RedhControl/RedhControlWatch/` or
  `RedhControl/RedhControlMac/` need no change to `project.pbxproj`.
- **RedhUI** holds the server's page and the setup for the iPhone and the Mac, inside
  `#if os(iOS) || os(macOS)`, so the Watch builds RedhUI without them. iOS-only modifiers there
  (keyboards, inline titles) go inside `#if os(iOS)`.
- **Forms on the Mac** default to the columns style, which showed the editors' labels twice and
  set the fields against the sheet's edges. RedhUI's forms say `.formStyle(.grouped)`. A grouped
  form on the Mac shows a field's own label, so `FieldRow` and `SecureRow` use
  `TextField(text:prompt:label:)` there, and `LabeledContent` with a trailing field on the
  iPhone. Buttons are push buttons on the Mac: `ButtonRow` sets a section's buttons side by side
  there, and gives each a row of its own on the iPhone.
- **A selected row** in the Mac's sidebar is blue, where a state's green is hard to read. There
  `backgroundProminence` is `.increased`, and `StateLine` turns to the secondary style, which is
  white on it.
- **The Mac's window** can't be seen while the MacBook's screen is locked: an app started then
  gets no connection to the window server. Check the shared screens in the iOS simulator, which
  renders anyway, and the Mac's own window when the screen is unlocked. `screencapture` works;
  capture the app's window only (`screencapture -l <window number>`), never the whole screen. An
  app started while another one is in front may stay behind it, with an inactive window (gray
  selection and buttons); `open -a` on the running app brings it to the front. A window on another
  Space isn't on screen, and a capture of it shows an old or empty picture: bring it over with
  `open -a` first. The app's windows include its menu bars, as wide as the screens; the main
  window is the one that is also tall.
- **The Mac app** keeps a setup and tokens of its own. Its Keychain is the login keychain: the
  data protection keychain failed there with -34018, "A required entitlement is not present.",
  since it needs a keychain access group, which only a provisioning profile grants, and the
  account was free then, with profiles that expired after 7 days. A rebuild signed by the same
  team reads the items of the build before without asking. `keychainOnTheMac` in RedhKit's tests
  has no access group either, so it fails as the app did. The demo keeps its secrets in memory.
- **Roosters** wake servers: a FRITZ!Box, or another server whose RedhAPI (0.2 or newer) sends
  the packet through `POST /v1/wake`. Setup format 2 has `rooster`; format 1's `boxID` is read as
  a FRITZ!Box rooster. A rooster server that didn't answer the last look can't wake: the app says
  to wake it first and doesn't wake the chain itself (the owner's choice). A silent server whose
  rooster server answers counts as probably down, as the FRITZ!Box's host list does. Shutting down
  a rooster warns, with `Setup.shutdownNote`, on iPhone, Mac and Watch.
- **The App Store** sells iPhone, Watch and Mac as one listing, which needs one bundle ID: the Mac
  app has `com.redhwire.redhcontrol` since 2026-11-24, and so a new sandbox and an empty setup.
  App Review needs the app without a homelab: the empty screens offer Try the Demo, which swaps
  in `Demo.monitor()` and never touches the setup or the Watch link. Each app has a
  `PrivacyInfo.xcprivacy` (no tracking, no data) and `ITSAppUsesNonExemptEncryption = NO`.
- **The icons** come from `Artwork/Home-Port.png`, the owner's artwork, through
  `scripts/make-icon.swift`. It has three flat colours (cream, teal, orange), so the dark and
  tinted icons recolour each pixel by its share of them. On white, the Mac's cream tile needs its
  shadow.
- **The System section** shows `GET /v1/system`, which a server's page asks for with the apps,
  side by side, every 10 seconds; a RedhAPI before 0.2.0 has none, and the section stays away. To
  see all of it in the Mac's window, which keeps its frame in the app's preferences (not
  readable from outside the sandbox), move the section up for a capture; don't show it twice.
  Two sections with the same row IDs in one Form put a row outside its card.
- **WatchConnectivity** doesn't exist on macOS, so `WatchLink` is inside
  `#if canImport(WatchConnectivity)`, and `swift test` never builds it; `WatchSync`, what it
  carries, is tested. The session holds its delegate weakly, so the apps keep the link. The demo
  never activates the link: it would replace the Watch's setup.
- **The shell is zsh:** an unquoted `$var` isn't split into words. Spell commands out instead of
  `set -- $var`.

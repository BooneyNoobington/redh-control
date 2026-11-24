# Redh Control on the App Store

One listing sells the iPhone app, with its Watch app, and the Mac app: they share the bundle ID
`com.redhwire.redhcontrol`, which App Store Connect calls a universal purchase. This page holds
what App Store Connect asks for, ready to paste, and what is still open.

## Still open

- **The pushes to GitHub.** The app is of no use without RedhAPI on the servers, and App Review
  may ask where users get it: from `https://github.com/BooneyNoobington/redh-api`, once it's
  pushed there, as `redh-control` and `redh-manager`.
- **The privacy policy and the support page,** both public, both on GitHub once pushed:
  - Privacy Policy URL: `https://github.com/BooneyNoobington/redh-control/blob/main/PRIVACY.md`;
  - Support URL: `https://github.com/BooneyNoobington/redh-control`, whose README leads to RedhAPI.
    It needs a way to reach you, such as the repository's issues.
- **Screenshots,** below.
- **The app's record:** in App Store Connect, Apps > + > New App, with the platforms iOS and
  macOS, the name, the bundle ID `com.redhwire.redhcontrol`, and an SKU such as `redh-control`.

## The GPL and the App Store

The apps are under GPL-3.0-only. As their only author, you may still sell or give them through
the App Store under Apple's terms: the GPL binds those who receive the code, not its owner. Code
that others contribute under the GPL can't simply go along, since Apple's terms add restrictions
the GPL forbids; VLC was taken off the App Store over this in 2011. Before taking contributions,
have contributors agree to distribution through the App Store, for instance with an exception for
it in the license notice.

## The listing

| Field | Text |
|---|---|
| Name | Redh Control |
| Subtitle | Wake & shut down your homelab |
| Category | Utilities |
| Price | Free |
| Age rating | 4+: every question answered with None or No |
| Keywords | homelab,server,wake on lan,wol,shutdown,self-hosted,nas,home server,router,power |
| Promotional text | Wake your homelab's servers up, shut them down safely, and see at a glance which ones are running: from your iPhone, Apple Watch or Mac. |

The limits are 30 characters for the subtitle, 100 for the keywords and 170 for the promotional
text; these have 29, 80 and 136. Apple's guidelines advise against other companies' trademarks in
the keywords, so FRITZ!Box appears in the description only.

**Description:**

> Redh Control keeps an eye on the servers of your homelab, wakes them up and shuts them down:
> from your iPhone, your Apple Watch and your Mac.
>
> • See at a glance which servers are up, which are probably down, and which are waking up or
> shutting down.
> • Wake a server up through its rooster: your FRITZ!Box, or another server of yours that stays on.
> • Shut a server down safely: RedhAPI on the server runs your own shutdown script.
> • Get warned before you shut down a server that wakes others, or one that is meant to stay on.
> • See the apps that redh-manager runs on a server.
> • Everything stays between your devices and your servers, and nothing goes anywhere else. TLS
> is always verified: with your own certificate authority, or with each server's own certificate,
> paired once with a code. No certificate authority or DNS names needed; IP addresses do.
>
> Redh Control needs RedhAPI, a small service, on each of your servers; the support page says how
> to set it up. To look around first, tap Try the Demo: a made-up homelab, no setup needed.

## App Privacy

Data collection: **No, we do not collect data from this app.** The apps talk only to the servers
and FRITZ!Boxes the user sets up, directly. Nothing reaches the developer or anyone else.

## Export compliance

Each app's Info.plist has `ITSAppUsesNonExemptEncryption = NO`. The apps use only the encryption
built into Apple's systems, HTTPS, and hashes for logins and certificate pins. App Store Connect
doesn't ask about encryption then.

## App Review

Sign-in required: no. Notes for the reviewer:

> Redh Control controls the user's own servers, which run a small service, RedhAPI. To try the app
> without servers, tap Try the Demo on the first screen, on iPhone, Apple Watch or Mac. It shows a
> made-up homelab, and every command answers as a real server would. End Demo returns to the empty
> setup.

## Screenshots

The demo makes them, without any network:

- **iPhone:** the 6.9-inch size, 1320 × 2868, for instance from the iPhone 17 Pro Max simulator.
  `xcrun simctl launch booted com.redhwire.redhcontrol -demo -open nas`, then
  `xcrun simctl io booted screenshot nas.png`.
- **Apple Watch:** one size of a current watch, from its simulator, with
  `xcrun simctl launch <watch> com.redhwire.redhcontrol.watchkitapp -demo`.
- **Mac:** 16:10, such as 2880 × 1800. The app's window with `-demo -open nas`, on a plain
  background of that size.

The simulators have to be installed first: Xcode > Settings > Components.

## Uploading

1. In Xcode, Product > Archive, with the RedhControl scheme and Any iOS Device. The archive holds
   the Watch app. Then Distribute App > App Store Connect.
2. The same with the RedhControlMac scheme and Any Mac.
3. Each build shows up in App Store Connect under TestFlight after processing; testing it
   yourself needs no review. Then add the builds to the version, and Submit for Review.

`MARKETING_VERSION` is 0.1 for all three apps. The App Store takes it, or make it 1.0 for the first
release. `CURRENT_PROJECT_VERSION`, the build number, has to grow with every upload.

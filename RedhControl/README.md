# RedhControl

The apps of Redh Control, in SwiftUI: for the iPhone, the Apple Watch and the Mac. Their logic is
in [RedhKit](Packages/RedhKit/), which all three share. The iPhone and the Mac also share the
server's page and the setup, in `RedhUI`.

| Screen | What it shows |
|---|---|
| Servers | Every server with its icon, its state and a line about it. While the app is in front, it looks every 10 seconds, every 3 while a command waits for its effect. Without servers: Set Up, and Try the Demo. |
| A server | Its state, Wake Up and Shut Down (which asks first), what RedhAPI reports, what the machine is doing (processor, temperature, power, memory, disks), its apps where redh-manager runs, and its setup. While it is waking, Wake Up Again sends the packet once more. |
| Setup | The CA's root certificate, the FRITZ!Boxes and the servers |

## Running it

Your signing team goes into `Config/Local.xcconfig`, a file of your own that git ignores:

```
DEVELOPMENT_TEAM = ABCDE12345
```

Xcode > Settings > Accounts shows the team's ID. Choosing the team under Signing & Capabilities
works too, but Xcode then writes it into `project.pbxproj`, where git sees it.

Then open `RedhControl.xcodeproj`, pick the RedhControl scheme and your iPhone, and run. It needs
iOS 17 or newer. An installed app keeps starting as long as its provisioning profile lasts: a year
with a paid Apple developer account, 7 days with a free one; then Xcode has to install it again.

Without a setup, the app offers Try the Demo: a made-up homelab without any network, five servers
in different states, which End Demo leaves. It's how App Review tries the app. The scheme's `-demo`
launch argument, off by default (Product > Scheme > Edit Scheme > Run > Arguments), starts with
the same demo.

## Setting it up

1. **The root certificate,** where RedhAPI runs behind Caddy with your CA: Setup > Import Root
   Certificate… with the root of your ACME CA as a file, PEM or DER; or copy its PEM and tap
   Paste. Servers paired with RedhAPI's own certificate don't need it.
2. **A FRITZ!Box,** if one is to wake servers up: Setup > Add FRITZ!Box, with its name, its host
   name, its IP address if you like, and a FRITZ!Box user with password. Then Fetch Certificate,
   compare the fingerprint, Trust This Certificate, and Save. The box needs "Allow access for
   applications" (TR-064) turned on.
3. **The servers:** Setup > Add Server, with:
   - the name; behind Caddy, RedhAPI's address follows it, `https://rapi.NAME.internal`;
   - the token that `redh-api token` printed, or the pairing code it printed along with it where
     RedhAPI has a certificate of its own;
   - the rooster and the MAC address;
   - whether it is always on;
   - an icon and a color.

A pairing code holds the token and the SHA-256 of RedhAPI's own certificate, which RedhAPI makes
where there's no CA, Caddy or DNS name. Pasted into Pairing Code, it sets both: Redh Control then
trusts that certificate alone, under any name or address of the server, and RedhAPI's address is
the server's own, such as `https://192.168.1.10:8470`. Nothing is trusted on first sight, and
nobody compares fingerprints. Forget the Pairing goes back to your CA.

The rooster wakes the server up, by the MAC address of its network card. It's one of the
FRITZ!Boxes, or another server of the setup that stays on, with RedhAPI 0.2 or newer, which sends
the Wake-on-LAN packet. A FRITZ!Box also tells whether it sees the server while RedhAPI doesn't
answer. A rooster server can't wake anybody while it's asleep itself: then Wake Up says to wake it
first.

Shutting down a server that is the rooster of others warns before: nothing else can wake them
while it's off. The warning names them, and what can wake the rooster itself.

An always-on server is one that should keep running. Shutting it down asks a second time: the app
first asks its rooster whether it could wake the server up again, and says so. A FRITZ!Box has to
know the server's MAC address; a rooster server has to be up, with RedhAPI 0.2 or newer. If it
can't, the server would have to be switched on by hand. The Watch doesn't offer Shut Down for it.

The setup is saved in the app's Application Support, tokens and passwords in the Keychain, on this
iPhone only. If iOS asks whether Redh Control may use the local network, allow it; it reaches
nothing otherwise.

## The Watch app

The Watch shows the same servers with their state. On a server's page it offers only the command
that makes sense: Wake Up for a server that sleeps (Wake Up Again while it is waking), Shut Down
(after asking) for one that is up and ready, unless it is always on.

It has no setup of its own. Whenever the setup, a token or a password changes, the iPhone app
sends them to the Watch through WatchConnectivity, and the Watch keeps them in its own Keychain.
So after installing, open the iPhone app once with the Watch nearby. The iPhone's demo never
reaches the Watch; without servers, the Watch offers Try the Demo of its own.

The Watch app is embedded in the iPhone app, and needs watchOS 10 or newer. To install it on your
Watch for the first time:

1. **Connect:** connect the iPhone to the Mac, and put the Mac and the Watch on the same Wi-Fi.
   Xcode reaches the Watch over Wi-Fi only, so a guest network that keeps devices apart, or a VPN
   on the Mac, stops it. Keep the Watch unlocked and nearby. Near its iPhone, the Watch may stay on
   Bluetooth; turning Bluetooth off on the iPhone (in Settings, not Control Center) can make it
   use Wi-Fi. Xcode > Window > Devices and Simulators then lists the Watch, and
   `xcrun devicectl list devices` shows it as paired.
2. **Developer Mode:** turn it on on the Watch, under Settings > Privacy & Security > Developer
   Mode; the Watch restarts. The setting appears once Xcode has seen the Watch.
3. **Run:** pick the RedhControlWatch scheme and your Watch by its name. Entries such as "Apple
   Watch SE 3 (40mm)" are simulators, not your Watch. The first run mounts a developer disk image
   on the Watch, which can take minutes and needs the Wi-Fi link all along: keep the Watch awake.

"Mismatched platform" means that scheme and destination don't fit: the RedhControl scheme with a
Watch, or the RedhControlWatch scheme with an iPhone. It also comes when Xcode doesn't see the
Watch at all, since the iPhone is then the only real device it can offer. Once the Watch is known
to Xcode, installing the iPhone app also brings the Watch app along, either automatically or from
the Watch app on the iPhone (Available Apps).

If Xcode's run times out ("Timed out while attempting to establish tunnel"), the app it has built
can go onto the Watch directly, with the Watch's identifier from `xcrun devicectl list devices`:

```bash
xcrun devicectl device install app --device WATCH-ID ~/Library/Developer/Xcode/DerivedData/RedhControl-*/Build/Products/Debug-watchos/RedhControlWatch.app
xcrun devicectl device process launch --device WATCH-ID com.redhwire.redhcontrol.watchkitapp
xcrun devicectl device capture screenshot --device WATCH-ID --destination shot.png
```

The Watch reaches the servers itself: through the iPhone when it is nearby, or over its own Wi-Fi.
It has no VPN of its own, so away from home, on its own Wi-Fi, it can't reach the homelab. Through
the iPhone, the FRITZ!Box answers it, but RedhAPI so far fails with a TLS error, although RedhKit
connects fine in the watchOS simulator.

In a Watch simulator, `-demo` works as on the iPhone:

```bash
xcrun simctl launch booted com.redhwire.redhcontrol.watchkitapp -demo
```

## The Mac app

The Mac shows the servers in a sidebar and the chosen one's page beside it: the same page as on
the iPhone, apps included. The gear in the toolbar opens the setup. To run it, pick the
RedhControlMac scheme and My Mac. It needs macOS 14 or newer, and runs in the App Sandbox,
allowed to connect to servers and to read the files you choose, such as the root certificate.

The Mac app has the iPhone app's bundle ID, `com.redhwire.redhcontrol`, so that the App Store sells
both, with the Watch app, as one. Before, it had one of its own, and so another sandbox: a Mac set
up before starts with an empty setup. Its old tokens stay in the login keychain, under
`com.redhwire.redhcontrol`, where Keychain Access can delete them.

The Mac keeps a setup of its own, entered as on the iPhone. Its tokens and passwords go into your
login keychain, which works without a provisioning profile. Give it tokens of its own, one per
server, so that RedhAPI's journal tells the devices apart and each token can be withdrawn alone.
On each server:

```bash
redh-api token redh-mac
```

The printed line goes under `[tokens]`, then `sudo systemctl restart redh-api`.

## Screens without tapping

Launch arguments open a screen directly, for trying things and for screenshots:

```bash
xcrun simctl launch booted com.redhwire.redhcontrol -demo -open nas
```

- `-demo`: the demo homelab;
- `-open NAME`: a server's page, `-open NAME -edit` its editor, `-open setup` the setup,
  `-open setup -box NAME` a FRITZ!Box's editor in it.

The Mac app takes the same arguments, for instance through `open`:

```bash
open "$(ls -d ~/Library/Developer/Xcode/DerivedData/RedhControl-*/Build/Products/Debug/'Redh Control.app' | head -1)" --args -demo -open nas
```

A screenshot of the booted simulator (a simulator with several displays, such as the iPhone Duo
was, needs `--display=primary` as well):

```bash
xcrun simctl io booted screenshot servers.png
```

## The project

`RedhControl.xcodeproj` keeps each app's sources as a synchronized folder: a new file in
`RedhControl/`, `RedhControlWatch/` or `RedhControlMac/` belongs to its app without changing the
project. RedhKit is a local package. `Config/Signing.xcconfig` is the base configuration of the
apps, and includes `Config/Local.xcconfig` if it's there.

`scripts/make-icon.swift` makes the app icons from the artwork, `Artwork/Home-Port.png` at the
top of the repository: the iPhone's light icon, which is the artwork itself, its dark and tinted
icons, and the Mac's icons in the Mac's rounded square. The artwork has three flat colours, so the
script recolours each pixel by its share of them:

```bash
swift scripts/make-icon.swift ../Artwork/Home-Port.png RedhControl/Assets.xcassets/AppIcon.appiconset RedhControlMac/Assets.xcassets/AppIcon.appiconset
```

The Watch's icon is a copy of the light one:

```bash
cp RedhControl/Assets.xcassets/AppIcon.appiconset/icon-ios-1024.png RedhControlWatch/Assets.xcassets/AppIcon.appiconset/icon-watch-1024.png
```

# Redh Control
A small ecosystem to perform basic functions in the homelab "RedhWire".

## Construction
Building is done by Claude Code.
Build request id: 1092A2B7-1508-4815-AEAE-4F94FC90D74A

## Target devices
- Apple Watch
- iPhones
- (Fitbit, potentially in the future)
- (Android, potentialle in the future)

## Functionality for the first version
- Guess wether a server is up or down
- Shut a server down
- Bring a server up

## General ecosystem
Apple Watch / iPhone -> request -> RedhAPI on server -> sends shutdown command

- The app on the device is driven by the user.
- The request travels through the LAN but is tls encrypted.
- Every server has an instance of RedhAPI (yet to be built). Default domain: rapi.{servername}.internal
- The API is managed by systemd and runs as an unprivileged user.

### Shutdown command
Every server has a binary or script called "redh-shut" that I'll provide myself. It lives at /usr/local/bin/redh-shut and needs root to run. You prepare the API, tell my what to enter via visudo and I'll provide redh-shut.

### Startup command
This is where we'll take advantage of the two facts that all server should be able to react to wol and that the entire LAN runs on FRiTZ!Boxes.

These should have an API that takes wol requests and sends them to the target devices.

## What's configured

### The Boxes first
What their local domains are (e.g. "arc.internal") and as a fallback their ips.

### The Devices
To which box they belong, what their MAC is and an authentication token for their respective RedhAPI. Since we're in the Appl ecosystem anyways, the iCloud keyring might be useful here.

What also would be nice: A selection of stock icons for the servers. This helps telling them apart on a phone's display.

## This project directory
It's empty besides this description. At least to subdirectories would be great.
1. RedhAPI
2. RedhControl App: The user facing app


## Possible improvements
- Add a failsafe for servers marked as "always on", asking the user if they're sure and / or able to bring the server back online reliably.
- Add the possibility to repeat a wake on lan request.

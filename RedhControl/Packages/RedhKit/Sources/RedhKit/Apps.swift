import Foundation

/// What `GET /v1/apps` answers: redh-manager's list of a server's apps, as `redh list --json`
/// writes it. RedhAPI's README shows it; redh-manager's describes the fields.
public struct AppsListing: Codable, Hashable, Sendable {
    /// Where the apps live, such as /opt/podman.
    public var root: String
    public var apps: [Entry]
    /// What runs; nil when Podman couldn't be asked.
    public var containers: Containers?
    /// What redh couldn't find out, such as why Podman didn't answer.
    public var warnings: [String]

    /// One app, as a line of `redh list`.
    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public var name: String
        /// How its sources are laid out, such as "quadlet/"; nil without sources.
        public var layout: String?
        public var units: Int
        /// The services whose being active counts.
        public var services: Int
        /// How many of them are active; nil when systemd couldn't be asked.
        public var active: Int?
        /// Its running containers; nil when Podman couldn't be asked.
        public var running: Int?
        /// "in sync", "outdated", "no" or "orphaned"; nil when there is nothing to install.
        public var installed: String?
        /// Its Caddy snippets.
        public var caddy: Int

        public var id: String { name }

        public init(name: String, layout: String? = nil, units: Int = 0, services: Int = 0, active: Int? = 0,
                    running: Int? = 0, installed: String? = nil, caddy: Int = 0) {
            self.name = name
            self.layout = layout
            self.units = units
            self.services = services
            self.active = active
            self.running = running
            self.installed = installed
            self.caddy = caddy
        }
    }

    public struct Containers: Codable, Hashable, Sendable {
        public var running: Int
        /// Running containers that belong to no app.
        public var inNoApp: [Container]

        enum CodingKeys: String, CodingKey {
            case running
            case inNoApp = "in_no_app"
        }
    }

    public struct Container: Codable, Hashable, Sendable {
        public var name: String
        public var image: String
        /// The systemd unit running it; nil when it was started some other way.
        public var unit: String?
    }
}

extension AppsListing.Entry {
    /// As redh's ACTIVE column: "2/2", "-" without services, "?" when systemd couldn't be asked.
    public var activeText: String {
        guard services > 0 else { return "-" }
        return active.map { "\($0)/\(services)" } ?? "?"
    }

    /// As redh's RUNNING column: the count, "-" for none, "?" when Podman couldn't be asked.
    public var runningText: String {
        running.map { $0 > 0 ? "\($0)" : "-" } ?? "?"
    }

    /// One line about the app, such as "2/2 active, 1 running, in sync".
    public var summary: String {
        var parts: [String] = []
        if services > 0 {
            let count = services == 1 ? "1 service" : "\(services) services"
            parts.append(active.map { "\($0)/\(services) active" } ?? "\(count), state unknown")
        }
        parts.append(running.map { "\($0) running" } ?? "running unknown")
        if let installed {
            parts.append(installed == "no" ? "not installed" : installed)
        }
        return parts.joined(separator: ", ")
    }
}

extension AppsListing {
    /// "2 containers running, 1 of them in no app", or that Podman can't say.
    public var containersSummary: String {
        guard let containers else { return "Podman can't say what runs." }
        let count = containers.running == 1 ? "1 container running" : "\(containers.running) containers running"
        return containers.inNoApp.isEmpty ? count : "\(count), \(containers.inNoApp.count) of them in no app"
    }
}

import Foundation

/// What `GET /v1/system` reports about a server's machine, as RedhAPI's README shows it. Whatever
/// RedhAPI can't read is nil.
public struct SystemReport: Codable, Hashable, Sendable {
    public var cpu: CPU
    public var temperature: Temperature
    public var power: Power
    public var memory: Memory
    public var swap: Swap
    public var disks: [Disk]

    public struct CPU: Codable, Hashable, Sendable {
        /// The processors the kernel counts, threads included.
        public var count: Int?
        /// How busy they were together, over the last few seconds.
        public var usagePercent: Double?
        /// The load averages of the last 1, 5 and 15 minutes.
        public var load: [Double]?
        /// The share of the last 10 seconds in which tasks waited for a processor.
        public var pressurePercent: Double?

        enum CodingKeys: String, CodingKey {
            case count, load
            case usagePercent = "usage_percent"
            case pressurePercent = "pressure_percent"
        }
    }

    public struct Temperature: Codable, Hashable, Sendable {
        public var celsius: Double?
        /// Where it comes from, such as "coretemp: Package id 0".
        public var sensor: String?
    }

    /// The processor's power, from its energy counters; not the whole machine's.
    public struct Power: Codable, Hashable, Sendable {
        public var watts: Double?
        /// The counters, such as "package-0"; nil where there are none.
        public var sensor: String?
        /// Why there is no power, such as a counter only root may read.
        public var problem: String?
    }

    public struct Memory: Codable, Hashable, Sendable {
        public var totalBytes: Int64?
        public var availableBytes: Int64?
        /// The share of the last 10 seconds in which tasks waited for memory.
        public var pressurePercent: Double?

        enum CodingKeys: String, CodingKey {
            case totalBytes = "total_bytes"
            case availableBytes = "available_bytes"
            case pressurePercent = "pressure_percent"
        }
    }

    public struct Swap: Codable, Hashable, Sendable {
        public var totalBytes: Int64?
        public var freeBytes: Int64?

        enum CodingKeys: String, CodingKey {
            case totalBytes = "total_bytes"
            case freeBytes = "free_bytes"
        }
    }

    /// A file system, by a path on it, as `disks` under `[system]` in RedhAPI's configuration names it.
    public struct Disk: Codable, Hashable, Sendable {
        public var path: String
        public var totalBytes: Int64?
        /// What's free on it for anyone but root.
        public var freeBytes: Int64?

        enum CodingKeys: String, CodingKey {
            case path
            case totalBytes = "total_bytes"
            case freeBytes = "free_bytes"
        }
    }
}

extension SystemReport {
    /// One line of the System section: a name, a value, and how full it is, from 0 to 1, where
    /// something can fill up.
    public struct Meter: Hashable, Sendable, Identifiable {
        public var name: String
        public var value: String
        public var fraction: Double?

        public var id: String { name }
    }

    /// The lines of the System section, in this order; what RedhAPI couldn't read is left out.
    /// Memory in units of 1024, disks in units of 1000, as macOS and Linux tools show them.
    public func meters(locale: Locale = .current) -> [Meter] {
        var meters: [Meter] = []
        if let usage = cpu.usagePercent {
            let threads = cpu.count.map { $0 == 1 ? ", 1 thread" : ", \($0) threads" } ?? ""
            meters.append(Meter(name: "Processor", value: "\(Int(usage.rounded()))% busy\(threads)", fraction: usage / 100))
        }
        if let load = cpu.load, !load.isEmpty {
            meters.append(Meter(name: "Load", value: load.map { String(format: "%.2f", $0) }.joined(separator: ", ")))
        }
        if let celsius = temperature.celsius {
            meters.append(Meter(name: "Temperature", value: "\(Int(celsius.rounded())) °C"))
        }
        if let watts = power.watts {
            meters.append(Meter(name: "Power", value: String(format: "%.1f W", watts)))
        }
        if let total = memory.totalBytes, let available = memory.availableBytes, total > 0 {
            meters.append(used(total - available, of: total, name: "Memory", style: .memory, locale: locale))
        }
        if let total = swap.totalBytes, let free = swap.freeBytes, total > 0 {
            meters.append(used(total - free, of: total, name: "Swap", style: .memory, locale: locale))
        }
        for disk in disks {
            if let total = disk.totalBytes, let free = disk.freeBytes, total > 0 {
                meters.append(used(total - free, of: total, name: disk.path, style: .file, locale: locale))
            }
        }
        return meters
    }

    /// What the section's footer says: when tasks waited for the processor or for memory, and why
    /// there is no power where the processor has energy counters.
    public var notes: [String] {
        var notes: [String] = []
        for (what, share) in [("a processor", cpu.pressurePercent), ("memory", memory.pressurePercent)] {
            if let share, share >= 1 {
                notes.append("Tasks waited for \(what) \(Int(share.rounded()))% of the last 10 seconds.")
            }
        }
        if power.watts == nil, power.sensor != nil, let problem = power.problem {
            notes.append(problem)
        }
        return notes
    }

    private func used(_ used: Int64, of total: Int64, name: String, style: ByteCountFormatStyle.Style,
                      locale: Locale) -> Meter {
        let format = ByteCountFormatStyle(style: style, locale: locale)
        return Meter(name: name, value: "\(format.format(used)) of \(format.format(total)) used",
                     fraction: Double(used) / Double(total))
    }
}

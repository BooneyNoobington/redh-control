import Foundation
import Testing
@testable import RedhKit

struct SystemReportTests {
    let english = Locale(identifier: "en_US")

    func example() throws -> SystemReport {
        try JSONDecoder().decode(SystemReport.self, from: try fixture("system.json"))
    }

    @Test func theExampleAsMeters() throws {
        let meters = try example().meters(locale: english)
        #expect(meters.map(\.name) == ["Processor", "Load", "Temperature", "Power", "Memory", "Swap", "/", "/srv/data"])
        #expect(meters.map(\.value) == ["7% busy, 8 threads", "0.42, 0.38, 0.35", "46 °C", "12.4 W",
                                        "6.68 GB of 15.26 GB used", "488.3 MB of 3.81 GB used",
                                        "69 GB of 250 GB used", "2.38 TB of 4 TB used"])
        #expect(meters.map { $0.fraction.map { ($0 * 1000).rounded() / 1000 } }
                == [0.073, nil, nil, nil, 0.438, 0.125, 0.276, 0.595])
    }

    @Test func pressureOnlyWhenTasksWaitedNoticeably() throws {
        var report = try example()
        #expect(report.notes == ["Tasks waited for a processor 1% of the last 10 seconds."])
        report.cpu.pressurePercent = 0.4
        report.memory.pressurePercent = 12.5
        #expect(report.notes == ["Tasks waited for memory 13% of the last 10 seconds."])
    }

    @Test func whyThereIsNoPowerOnlyWhereTheProcessorHasCounters() throws {
        var report = try example()
        report.cpu.pressurePercent = nil
        report.power = SystemReport.Power(watts: nil, sensor: "package-0", problem: "Only root may read it.")
        #expect(report.notes == ["Only root may read it."])
        #expect(!report.meters(locale: english).map(\.name).contains("Power"))
        report.power = SystemReport.Power(watts: nil, sensor: nil, problem: "There is no energy counter (RAPL) for the processor.")
        #expect(report.notes.isEmpty)
    }

    @Test func oneThreadAndNoSwap() throws {
        var report = try example()
        report.cpu.count = 1
        report.swap = SystemReport.Swap(totalBytes: 0, freeBytes: 0)
        let meters = report.meters(locale: english)
        #expect(meters.first?.value == "7% busy, 1 thread")
        #expect(!meters.map(\.name).contains("Swap"))
    }
}

@MainActor
struct DemoSystemTests {
    @Test func theNasIsQuietTheMediaServerBusy() async throws {
        let monitor = Demo.monitor()
        let nas = try #require(monitor.setup.servers.first { $0.name == "nas" })
        let media = try #require(monitor.setup.servers.first { $0.name == "media" })
        #expect(try await monitor.system(of: nas).power.watts == 12.4)
        let busy = try await monitor.system(of: media)
        #expect(busy.notes == ["Tasks waited for a processor 4% of the last 10 seconds.",
                               "Only root may read /sys/class/powercap/intel-rapl:0/energy_uj; RedhAPI's README says how to let RedhAPI read it."])
        #expect(busy.meters().first { $0.name == "Memory" }?.fraction == 0.8)
    }

    @Test func serversThatArentUpHaveNoReport() async throws {
        let monitor = Demo.monitor()
        let backup = try #require(monitor.setup.servers.first { $0.name == "backup" })
        await #expect(throws: TransportError.self) {
            try await monitor.system(of: backup)
        }
    }
}

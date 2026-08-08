import AppKit
import Testing
@testable import Ghostty

@MainActor
@Suite
struct ManagedWindowRegistryTests {
    private final class Topology {
        var windows: [NSWindow]
        var groupByWindow: [ObjectIdentifier: Int]

        init(_ groups: [[NSWindow]]) {
            self.windows = groups.flatMap { $0 }
            self.groupByWindow = [:]
            setGroups(groups)
        }

        func setGroups(_ groups: [[NSWindow]]) {
            windows = groups.flatMap { $0 }
            groupByWindow = [:]
            for (group, members) in groups.enumerated() {
                for window in members {
                    groupByWindow[ObjectIdentifier(window)] = group
                }
            }
        }

        func members(for window: NSWindow) -> [NSWindow] {
            guard let group = groupByWindow[ObjectIdentifier(window)] else { return [window] }
            return windows.filter { groupByWindow[ObjectIdentifier($0)] == group }
        }
    }

    private func makeRegistry(
        topology: Topology,
        notificationCenter: NotificationCenter? = nil
    ) -> ManagedWindowRegistry {
        ManagedWindowRegistry(
            windowProvider: { topology.windows },
            groupProvider: { topology.members(for: $0) },
            notificationCenter: notificationCenter
        )
    }

    @Test func lazyEntrySurvivesDivergenceWithSeniorMember() {
        let first = NSWindow()
        let second = NSWindow()
        let topology = Topology([[first, second]])
        let registry = makeRegistry(topology: topology)

        let original = registry.entries().first!
        _ = registry.putMetadata(id: original.id, data: ["role": .string("managed")])

        topology.setGroups([[first], [second]])
        let splitEntries = registry.entries()

        #expect(splitEntries.count == 2)
        let firstEntry = registry.entry(for: first)
        let secondEntry = registry.entry(for: second)
        #expect(firstEntry?.id == original.id)
        #expect(firstEntry?.metadata.data["role"] == .string("managed"))
        #expect(secondEntry?.id != original.id)
        #expect(secondEntry?.metadata.data.isEmpty == true)
    }

    @Test func metadataEntryWinsConvergenceOverSeniorEmptyEntry() {
        let first = NSWindow()
        let second = NSWindow()
        let topology = Topology([[first], [second]])
        let registry = makeRegistry(topology: topology)

        let initial = registry.entries()
        let seniorEmpty = initial[0]
        let juniorManaged = initial[1]
        _ = registry.putMetadata(id: juniorManaged.id, data: ["key": .string("console")])

        topology.setGroups([[first, second]])
        let merged = registry.entries()

        #expect(merged.count == 1)
        #expect(merged[0].id == juniorManaged.id)
        #expect(merged[0].metadata.data["key"] == .string("console"))
        #expect(registry.entry(id: seniorEmpty.id) == nil)
    }

    @Test func seniorMetadataEntryWinsManagedManagedConvergence() {
        let first = NSWindow()
        let second = NSWindow()
        let topology = Topology([[first], [second]])
        let registry = makeRegistry(topology: topology)

        let initial = registry.entries()
        _ = registry.putMetadata(id: initial[0].id, data: ["key": .string("senior")])
        _ = registry.putMetadata(id: initial[1].id, data: ["key": .string("junior")])

        topology.setGroups([[first, second]])
        let merged = registry.entries()

        #expect(merged.count == 1)
        #expect(merged[0].id == initial[0].id)
        #expect(merged[0].metadata.data["key"] == .string("senior"))
        #expect(registry.entry(id: initial[1].id) == nil)
    }

    @Test func closeNotificationKeepsSurvivorsAndRetiresLastMember() {
        let first = NSWindow()
        let second = NSWindow()
        let topology = Topology([[first, second]])
        let center = NotificationCenter()
        let registry = makeRegistry(topology: topology, notificationCenter: center)

        let entry = registry.entries().first!
        _ = registry.putMetadata(id: entry.id, data: ["key": .string("stable")])

        center.post(name: NSWindow.willCloseNotification, object: first)
        let survivor = registry.entry(id: entry.id)
        #expect(survivor?.liveWindows.count == 1)
        #expect(survivor?.liveWindows.first === second)
        #expect(survivor?.metadata.data["key"] == .string("stable"))

        center.post(name: NSWindow.willCloseNotification, object: second)
        #expect(registry.entry(id: entry.id) == nil)
        #expect(registry.entries().isEmpty)
    }

    @Test func findOrCreateMatchingUsesOldestExactAndEntry() {
        let first = NSWindow()
        let second = NSWindow()
        let topology = Topology([[first], [second]])
        let registry = makeRegistry(topology: topology)
        let entries = registry.entries()

        _ = registry.putMetadata(
            id: entries[0].id,
            data: ["role": .string("viewer"), "ordinal": .int(1)]
        )
        _ = registry.putMetadata(
            id: entries[1].id,
            data: ["role": .string("viewer"), "ordinal": .int(1)]
        )

        let match = registry.firstEntry(matching: [
            "role": .string("viewer"),
            "ordinal": .int(1),
        ])
        #expect(match?.id == entries[0].id)
        #expect(registry.firstEntry(matching: ["ordinal": .string("1")]) == nil)
    }
}

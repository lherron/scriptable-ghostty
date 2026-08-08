import AppKit
import Foundation

/// Process-lifetime identity and metadata for visible terminal tab groups.
///
/// A native Ghostty tab owns its own `NSWindow` and controller, so managed
/// window identity cannot live on a controller. This registry instead derives
/// ownership from the live AppKit tab-group topology on every access.
@MainActor
final class ManagedWindowRegistry: NSObject {
    final class Entry {
        let id: UUID
        let sequence: UInt64
        var metadata: MetadataState
        fileprivate var members: [Weak<NSWindow>]

        fileprivate init(
            id: UUID = UUID(),
            sequence: UInt64,
            metadata: MetadataState,
            windows: [NSWindow]
        ) {
            self.id = id
            self.sequence = sequence
            self.metadata = metadata
            self.members = windows.map(Weak.init)
        }

        var liveWindows: [NSWindow] {
            members.compactMap(\.value)
        }
    }

    typealias WindowProvider = @MainActor () -> [NSWindow]
    typealias GroupProvider = @MainActor (NSWindow) -> [NSWindow]

    private final class WindowRecord {
        weak var window: NSWindow?
        let sequence: UInt64

        init(window: NSWindow, sequence: UInt64) {
            self.window = window
            self.sequence = sequence
        }
    }

    private struct Group {
        var windows: [NSWindow]
    }

    private let windowProvider: WindowProvider
    private let groupProvider: GroupProvider
    private let notificationCenter: NotificationCenter?
    private var entriesStorage: [Entry] = []
    private var windowRecords: [ObjectIdentifier: WindowRecord] = [:]
    private var closedWindows: [ObjectIdentifier: Weak<NSWindow>] = [:]
    private var nextEntrySequence: UInt64 = 0
    private var nextWindowSequence: UInt64 = 0

    init(
        windowProvider: @escaping WindowProvider = {
            TerminalController.all.compactMap(\.window)
        },
        groupProvider: @escaping GroupProvider = { window in
            window.tabGroup?.windows ?? [window]
        },
        notificationCenter: NotificationCenter? = .default
    ) {
        self.windowProvider = windowProvider
        self.groupProvider = groupProvider
        self.notificationCenter = notificationCenter
        super.init()

        notificationCenter?.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    deinit {
        notificationCenter?.removeObserver(self)
    }

    /// Refresh registry ownership without otherwise reading or mutating it.
    func touch() {
        refresh()
    }

    /// All live entries in creation order.
    func entries() -> [Entry] {
        refresh()
        return entriesStorage.sorted { $0.sequence < $1.sequence }
    }

    func entry(id: UUID) -> Entry? {
        refresh()
        return entriesStorage.first { $0.id == id }
    }

    /// Lazily ensure an entry for a normal terminal window.
    func entry(for window: NSWindow) -> Entry? {
        refresh(additionalWindows: [window])
        return entriesStorage.first { entry in
            entry.liveWindows.contains { $0 === window }
        }
    }

    /// Register a window created by the API with metadata before the synchronous
    /// MainActor handler returns. A refresh immediately applies convergence rules
    /// if AppKit has already joined the window to an existing tab group.
    func registerCreated(window: NSWindow, metadata: MetadataState) -> Entry? {
        let created = makeEntry(metadata: metadata, windows: [window])
        entriesStorage.append(created)
        refresh(additionalWindows: [window])
        return entriesStorage.first { entry in
            entry.liveWindows.contains { $0 === window }
        }
    }

    func firstEntry(matching metadata: [String: JSONValue]) -> Entry? {
        refresh()
        return entriesStorage
            .filter { entry in
                metadata.allSatisfy { key, value in
                    entry.metadata.data[key] == value
                }
            }
            .min { $0.sequence < $1.sequence }
    }

    func patchMetadata(id: UUID, patch: [String: JSONValue]) -> Entry? {
        refresh()
        guard let entry = entriesStorage.first(where: { $0.id == id }) else { return nil }
        entry.metadata.applyMerge(patch)
        return entry
    }

    func putMetadata(id: UUID, data: [String: JSONValue]) -> Entry? {
        refresh()
        guard let entry = entriesStorage.first(where: { $0.id == id }) else { return nil }
        entry.metadata = MetadataState(data: data)
        return entry
    }

    func deleteMetadata(id: UUID) -> Entry? {
        putMetadata(id: id, data: [:])
    }

    func preferredWindow(for id: UUID) -> NSWindow? {
        guard let entry = entry(id: id) else { return nil }
        let windows = entry.liveWindows
        if let selected = windows.first?.tabGroup?.selectedWindow,
           windows.contains(where: { $0 === selected }) {
            return selected
        }
        return windows.first
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        guard entriesStorage.contains(where: { entry in
            entry.liveWindows.contains { $0 === closingWindow }
        }) else { return }

        closedWindows[ObjectIdentifier(closingWindow)] = Weak(closingWindow)

        // willClose is synchronous on the main thread. Explicitly exclude the
        // closer because AppKit may still report it in tabGroup.windows during
        // the notification; surviving members are re-adopted in this same turn.
        refresh(excluding: closingWindow)
    }

    private func refresh(
        excluding excludedWindow: NSWindow? = nil,
        additionalWindows: [NSWindow] = []
    ) {
        let windows = uniqueWindows(
            windowProvider() + additionalWindows,
            excluding: excludedWindow
        )
        let groups = groups(for: windows, excluding: excludedWindow)

        var groupIndexByWindow: [ObjectIdentifier: Int] = [:]
        for (index, group) in groups.enumerated() {
            for window in group.windows {
                groupIndexByWindow[ObjectIdentifier(window)] = index
                ensureWindowRecord(for: window)
            }
        }

        // Divergence: each existing entry follows the group containing its most
        // senior still-live member. Entries with no current members are dead.
        var claimsByGroup: [Int: [Entry]] = [:]
        for entry in entriesStorage {
            let candidates = entry.liveWindows.compactMap { window -> (Int, UInt64)? in
                let identifier = ObjectIdentifier(window)
                guard let groupIndex = groupIndexByWindow[identifier],
                      let sequence = windowRecords[identifier]?.sequence else { return nil }
                return (groupIndex, sequence)
            }

            guard let target = candidates.min(by: { $0.1 < $1.1 }) else { continue }
            claimsByGroup[target.0, default: []].append(entry)
        }

        var refreshed: [Entry] = []
        for (index, group) in groups.enumerated() {
            if let claims = claimsByGroup[index], !claims.isEmpty {
                // Convergence: metadata-bearing entries outrank empty lazy ones;
                // sequence is the total-order tie break. Losing IDs and metadata
                // dissolve rather than merge.
                let winner = claims.min { lhs, rhs in
                    let lhsHasMetadata = !lhs.metadata.data.isEmpty
                    let rhsHasMetadata = !rhs.metadata.data.isEmpty
                    if lhsHasMetadata != rhsHasMetadata {
                        return lhsHasMetadata && !rhsHasMetadata
                    }
                    return lhs.sequence < rhs.sequence
                }!
                winner.members = group.windows.map(Weak.init)
                refreshed.append(winner)
            } else {
                refreshed.append(makeEntry(metadata: .empty, windows: group.windows))
            }
        }

        entriesStorage = refreshed.sorted { $0.sequence < $1.sequence }
        windowRecords = windowRecords.filter { _, record in record.window != nil }
        closedWindows = closedWindows.filter { _, window in window.value != nil }
    }

    private func groups(for windows: [NSWindow], excluding excludedWindow: NSWindow?) -> [Group] {
        let allowed = Set(windows.map(ObjectIdentifier.init))
        var assigned = Set<ObjectIdentifier>()
        var result: [Group] = []

        // Resolve connected components rather than trusting a single snapshot.
        // This tolerates transient AppKit reads while tabs are moving.
        for seed in windows {
            let seedID = ObjectIdentifier(seed)
            guard !assigned.contains(seedID) else { continue }

            var groupWindows: [NSWindow] = []
            var queued: [NSWindow] = [seed]
            var queuedIDs: Set<ObjectIdentifier> = [seedID]

            while !queued.isEmpty {
                let window = queued.removeFirst()
                let identifier = ObjectIdentifier(window)
                guard allowed.contains(identifier), !assigned.contains(identifier) else { continue }
                assigned.insert(identifier)
                groupWindows.append(window)

                let related = groupProvider(window)
                for candidate in related where candidate !== excludedWindow {
                    let candidateID = ObjectIdentifier(candidate)
                    if allowed.contains(candidateID),
                       !assigned.contains(candidateID),
                       queuedIDs.insert(candidateID).inserted {
                        queued.append(candidate)
                    }
                }
            }

            if !groupWindows.isEmpty {
                // Preserve AppKit tab order where possible. Any transient member
                // not returned by the seed snapshot stays deterministically last.
                let preferredOrder = groupProvider(seed).filter { $0 !== excludedWindow }
                let order = Dictionary(uniqueKeysWithValues: preferredOrder.enumerated().map {
                    (ObjectIdentifier($0.element), $0.offset)
                })
                groupWindows.sort { lhs, rhs in
                    let left = order[ObjectIdentifier(lhs)] ?? Int.max
                    let right = order[ObjectIdentifier(rhs)] ?? Int.max
                    if left != right { return left < right }
                    return windowSequence(for: lhs) < windowSequence(for: rhs)
                }
                result.append(Group(windows: groupWindows))
            }
        }

        return result
    }

    private func uniqueWindows(_ windows: [NSWindow], excluding excludedWindow: NSWindow?) -> [NSWindow] {
        var seen = Set<ObjectIdentifier>()
        return windows.filter { window in
            guard window !== excludedWindow else { return false }
            let identifier = ObjectIdentifier(window)
            if let closed = closedWindows[identifier], closed.value === window {
                return false
            }
            return seen.insert(identifier).inserted
        }
    }

    private func makeEntry(metadata: MetadataState, windows: [NSWindow]) -> Entry {
        let entry = Entry(
            sequence: nextEntrySequence,
            metadata: metadata,
            windows: windows
        )
        nextEntrySequence &+= 1
        for window in windows {
            ensureWindowRecord(for: window)
        }
        return entry
    }

    private func ensureWindowRecord(for window: NSWindow) {
        let identifier = ObjectIdentifier(window)
        if let record = windowRecords[identifier], record.window === window { return }
        windowRecords[identifier] = WindowRecord(window: window, sequence: nextWindowSequence)
        nextWindowSequence &+= 1
    }

    private func windowSequence(for window: NSWindow) -> UInt64 {
        ensureWindowRecord(for: window)
        return windowRecords[ObjectIdentifier(window)]!.sequence
    }
}

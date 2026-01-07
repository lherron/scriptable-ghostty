import Foundation

/// Manages subscriptions to terminal output streams.
/// Used by the API to stream raw PTY output to external consumers.
actor OutputStreamManager {
    static let shared = OutputStreamManager()

    private var subscribers: [String: [UUID: AsyncStream<Data>.Continuation]] = [:]

    /// Subscribe to output from a specific surface
    func subscribe(surfaceId: String) -> AsyncStream<Data> {
        let subscriptionId = UUID()

        // Use makeStream to get both stream and continuation synchronously
        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)

        // Register subscriber immediately (we're already in actor context)
        if subscribers[surfaceId] == nil {
            subscribers[surfaceId] = [:]
        }
        subscribers[surfaceId]?[subscriptionId] = continuation

        // Set up cleanup handler
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeSubscriber(surfaceId: surfaceId, id: subscriptionId)
            }
        }

        return stream
    }

    /// Broadcast data to all subscribers for a surface
    func broadcast(surfaceId: String, data: Data) {
        guard let subs = subscribers[surfaceId] else { return }
        for (_, continuation) in subs {
            continuation.yield(data)
        }
    }

    /// Check if a surface has any active subscribers
    func hasSubscribers(surfaceId: String) -> Bool {
        guard let subs = subscribers[surfaceId] else { return false }
        return !subs.isEmpty
    }

    private func removeSubscriber(surfaceId: String, id: UUID) {
        subscribers[surfaceId]?.removeValue(forKey: id)
        // Clean up empty entries
        if subscribers[surfaceId]?.isEmpty == true {
            subscribers.removeValue(forKey: surfaceId)
        }
    }
}

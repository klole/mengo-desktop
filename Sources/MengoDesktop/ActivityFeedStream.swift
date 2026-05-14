import Foundation

/// Minimal slice of `MemoryDB` that `ActivityFeedStream` needs — declared so
/// tests can stub the source without standing up a real SQLite file.
protocol ActivityFeedSource: Sendable {
    func recentActivity(sinceFrameID: Int64, sinceAudioID: Int64, limit: Int) async throws -> [ActivityEvent]
    func lastFrameID() async throws -> Int64?
    func lastAudioID() async throws -> Int64?
}

extension MemoryDB: ActivityFeedSource {}

/// Polls the recorder DB on a fixed cadence and yields the new events each
/// tick. Cursor advances per batch so the source's `WHERE id > ?` clauses
/// only return fresh rows. Errors don't terminate the stream — the loop
/// pauses for `backoff` and tries again, so a momentarily locked DB doesn't
/// kill the live rail.
///
/// First yield contains up to `limit` recent rows (the cursors start at 0),
/// which gives the UI an immediate snapshot of recent activity at launch.
struct ActivityFeedStream: Sendable {
    let source: ActivityFeedSource
    var interval: Duration = .seconds(5)
    var backoff: Duration = .seconds(30)
    var limit: Int = 50

    func events() -> AsyncThrowingStream<[ActivityEvent], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var lastFrameID: Int64 = 0
                var lastAudioID: Int64 = 0
                while !Task.isCancelled {
                    do {
                        let batch = try await source.recentActivity(
                            sinceFrameID: lastFrameID,
                            sinceAudioID: lastAudioID,
                            limit: limit
                        )
                        if !batch.isEmpty {
                            for event in batch {
                                switch event {
                                case .screenshot(let id, _, _, _), .urlVisited(let id, _, _, _):
                                    lastFrameID = max(lastFrameID, id)
                                case .transcription(let id, _, _):
                                    lastAudioID = max(lastAudioID, id)
                                }
                            }
                            continuation.yield(batch)
                        }
                        try await Task.sleep(for: interval)
                    } catch is CancellationError {
                        break
                    } catch {
                        // Transient DB error (e.g. locked, brief recorder write storm).
                        // Hold and try again rather than tearing down the stream.
                        try? await Task.sleep(for: backoff)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

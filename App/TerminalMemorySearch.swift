import Foundation
import Database
import Search
import Shared

/// Shared terminal + frame memory search used by `TerminalMemoryService` and `RetraceCLI` (read-only path).
public enum TerminalMemorySearch {
    public static func makePayload(
        query: String,
        scope: TerminalMemorySearchScope,
        limit: Int,
        database: any DatabaseProtocol,
        search: any SearchProtocol,
        allowAgentFrameSearch: Bool
    ) async throws -> TerminalMemorySearchPayload {
        var terminalResults: [TerminalTaskSearchResult] = []
        var frameResults: [TerminalMemoryFrameHit] = []

        if scope != .frames {
            terminalResults = try await database.searchTerminalTasks(
                query: query,
                bundleID: nil,
                from: nil,
                to: nil,
                limit: limit
            )
        }

        if scope != .terminal {
            guard allowAgentFrameSearch else {
                throw TerminalMemoryError.frameSearchDisabled
            }

            let searchResults = try await search.search(
                query: SearchQuery(
                    text: query,
                    limit: limit,
                    mode: .all,
                    sortOrder: .newestFirst
                )
            )

            for result in searchResults.results.prefix(limit) {
                let terminalTask = try? await database.getTerminalTaskForFrame(frameID: result.id)
                frameResults.append(
                    TerminalMemoryFrameHit(
                        frameID: result.id,
                        timestamp: result.timestamp,
                        appBundleID: result.metadata.appBundleID,
                        windowName: result.metadata.windowName,
                        deeplinkURL: RetraceTimelineDeeplink.string(for: result.timestamp),
                        terminalTask: terminalTask,
                        snippet: result.snippet,
                        relevanceScore: result.relevanceScore,
                        matchedText: result.matchedText
                    )
                )
            }
        }

        return TerminalMemorySearchPayload(terminal: terminalResults, frames: frameResults)
    }
}

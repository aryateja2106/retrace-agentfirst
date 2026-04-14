import Foundation

/// Shared timeline deeplink construction for terminal memory and CLI.
public enum RetraceTimelineDeeplink {
    public static func url(for timestamp: Date) -> URL {
        var components = URLComponents()
        components.scheme = "retrace"
        components.host = "timeline"
        components.queryItems = [
            URLQueryItem(name: "t", value: String(Int64(timestamp.timeIntervalSince1970 * 1_000)))
        ]
        return components.url ?? URL(string: "retrace://timeline")!
    }

    public static func string(for timestamp: Date) -> String {
        url(for: timestamp).absoluteString
    }
}

import Foundation

/// Shared registry for supported terminal applications and their normalized window titles.
public enum TerminalBundleRegistry {
    public static let warpBundleID = "dev.warp.Warp-Stable"
    public static let terminalBundleID = "com.apple.Terminal"
    public static let iTermBundleID = "com.googlecode.iterm2"

    public static let supportedBundleIDs: Set<String> = [
        warpBundleID,
        terminalBundleID,
        iTermBundleID
    ]

    public static func isSupportedApp(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return supportedBundleIDs.contains(bundleID)
    }

    public static func bundleID(forTermProgram termProgram: String?) -> String {
        switch termProgram?.lowercased() {
        case "warpterminal", "warp":
            return warpBundleID
        case "apple_terminal":
            return terminalBundleID
        case "iterm.app", "iterm2":
            return iTermBundleID
        default:
            return warpBundleID
        }
    }

    public static func normalizedWindowName(_ windowName: String?, bundleID: String?) -> String? {
        guard let rawWindowName = windowName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawWindowName.isEmpty else {
            return nil
        }

        var normalized = rawWindowName
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if isSupportedApp(bundleID) {
            normalized = normalized
                .replacingOccurrences(
                    of: #"^[\*\u2022\-\u25CF]\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: #"\s+[—-]\s+(Warp|Terminal|iTerm2)$"#,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
                .replacingOccurrences(
                    of: #"^\s*~/"#,
                    with: "~/",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalized.isEmpty ? nil : normalized
    }
}

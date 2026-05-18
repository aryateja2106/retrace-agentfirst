import SwiftUI
import Shared

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case capture = "Capture"
    case storage = "Data"
    case context = "Context"
    case voice = "Voice"
    case privacy = "Privacy"
    case power = "Power"
    case tags = "Tags"
    case advanced = "Advanced"

    public var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .capture: return "video"
        case .storage: return "externaldrive"
        case .context: return "doc.text.magnifyingglass"
        case .voice: return "waveform"
        case .privacy: return "lock.shield"
        case .power: return "bolt.fill"
        case .tags: return "tag"
        case .advanced: return "wrench.and.screwdriver"
        }
    }

    var description: String {
        switch self {
        case .general: return "Startup, appearance, and shortcuts"
        case .capture: return "Frame rate, resolution, and display options"
        case .storage: return "Retention, rewind, and database locations"
        case .context: return "Agent CLI and local journal summaries"
        case .voice: return "Dictation, output, and voice command preferences"
        case .privacy: return "Encryption, exclusions, and permissions"
        case .power: return "OCR processing and battery optimization"
        case .tags: return "Manage and delete tags"
        case .advanced: return "Database, encoding, and developer tools"
        }
    }

    var gradient: LinearGradient {
        .retraceAccentGradient
    }

    func resetAction(for view: SettingsView) -> (() -> Void)? {
        switch self {
        case .general:
            return { view.resetGeneralSettings() }
        case .capture:
            return { view.resetCaptureSettings() }
        case .storage:
            return { view.resetStorageSettings() }
        case .context:
            return { view.resetContextSettings() }
        case .voice:
            return { view.resetVoiceSettings() }
        case .privacy:
            return { view.resetPrivacySettings() }
        case .power:
            return { view.resetPowerSettings() }
        case .advanced:
            return { view.resetAdvancedSettings() }
        case .tags:
            return nil
        }
    }
}

enum VoiceToggleMode: String, CaseIterable, Identifiable {
    case holdToTalk = "Hold to Talk"
    case toggle = "Toggle"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .holdToTalk:
            return "Listen only while the shortcut is held"
        case .toggle:
            return "Start and stop listening with each shortcut press"
        }
    }
}

enum VoiceOutputMode: String, CaseIterable, Identifiable {
    case clipboard = "Clipboard"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .clipboard:
            return "Place transcribed text on the clipboard"
        }
    }
}

enum ThemePreference: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

enum TimelineScrollOrientation: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .horizontal:
            return "Left/Right"
        case .vertical:
            return "Up/Down"
        }
    }

    var displayName: String {
        shortLabel
    }

    var description: String {
        switch self {
        case .horizontal:
            return "Use left/right scroll movement to scrub the timeline"
        case .vertical:
            return "Use up/down scroll movement to scrub the timeline"
        }
    }
}

enum CaptureResolution: String, CaseIterable, Identifiable {
    case original = "Original"
    case uhd4k = "4K"
    case fullHD = "1080p"
    case hd = "720p"

    var id: String { rawValue }
}

enum CompressionQuality: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case lossless = "Lossless"

    var id: String { rawValue }
}

enum PermissionStatus: String {
    case granted = "Granted"
    case denied = "Denied"
    case notDetermined = "Not Determined"
}

struct ExcludedAppInfo: Codable, Identifiable, Equatable {
    let bundleID: String
    let name: String
    let iconPath: String?

    var id: String { bundleID }

    static func from(appURL: URL) -> ExcludedAppInfo? {
        guard let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier else {
            return nil
        }

        let name = FileManager.default.displayName(atPath: appURL.path)
            .replacingOccurrences(of: ".app", with: "")

        return ExcludedAppInfo(
            bundleID: bundleID,
            name: name,
            iconPath: appURL.path
        )
    }
}

enum QuickDeleteOption: String, Identifiable {
    case fiveMinutes
    case oneHour
    case oneDay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fiveMinutes: return "last 5 minutes"
        case .oneHour: return "last hour"
        case .oneDay: return "last 24 hours"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .fiveMinutes: return 5 * 60
        case .oneHour: return 60 * 60
        case .oneDay: return 24 * 60 * 60
        }
    }

    var cutoffDate: Date {
        Date().addingTimeInterval(-timeInterval)
    }
}

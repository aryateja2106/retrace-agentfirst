import Foundation

/// Single source of truth for arya-retrace bundle identity, preference domain, and related IDs.
public enum AryaRetraceIdentity {
    public static let bundleIdentifier = "dev.arya.arya-retrace"

    /// Preference suite / `defaults` domain (matches bundle ID).
    public static let userDefaultsSuiteName = bundleIdentifier

    public static let logSubsystem = bundleIdentifier

    public static let masterKeyKeychainService = "\(bundleIdentifier).masterkey"

    /// SQLite encryption keychain (see `AppPaths.keychainService`).
    public static let databaseKeychainService = "\(bundleIdentifier).database"

    public static let keychainErrorDomain = "\(bundleIdentifier).keychain"

    public static let crashRecoveryLaunchAgentLabel = "\(bundleIdentifier).crash-recovery"

    public static let crashRecoveryLaunchAgentPlistName = "\(crashRecoveryLaunchAgentLabel).plist"

    public static let crashRecoveryHelperBundleIdentifier = "\(bundleIdentifier).crashrecoveryhelper"

    /// Stable path for single-instance lock (hyphenated for filesystem safety).
    public static var singleInstanceLockPath: String {
        let safe = bundleIdentifier.replacingOccurrences(of: ".", with: "-")
        return "/tmp/\(safe).instance.lock"
    }

    public static let externalDashboardRevealNotification = Notification.Name("\(bundleIdentifier).externalDashboardReveal")

    /// Info.plist key: when true, Sparkle is not initialized (private / local builds).
    public static let disableSparkleUpdatesInfoKey = "AryaRetraceDisableSparkleUpdates"

    /// Human-readable product name for menus and alerts.
    public static let displayName = "arya-retrace"

    /// Default Application Support subfolder (last path component) for app-owned files.
    public static let applicationSupportFolderName = "arya-retrace"

    /// Default storage root folder name under the user's home (legacy layout used `Retrace`).
    public static let defaultStorageFolderName = "arya-retrace"
}

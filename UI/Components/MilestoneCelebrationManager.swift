import SwiftUI
import Combine
import App
import Shared

/// Manages milestone celebration dialogs that appear at 10, 100, 1000, and 10000 hours of screen time
/// Each milestone is shown only once
///
/// Screen time is tracked persistently in UserDefaults so milestones survive database moves/resets.
/// Uses timestamp-based tracking to only count segments created after the last checkpoint.
@MainActor
public class MilestoneCelebrationManager: ObservableObject {

    // MARK: - Published State

    /// The current milestone to celebrate (nil if none)
    @Published public var currentMilestone: Milestone? = nil

    // MARK: - Color Theme

    /// Available color themes for the app accent color
    public enum ColorTheme: String, CaseIterable, Identifiable, Sendable {
        case blue = "blue"
        case monochrome = "monochrome"
        case gold = "gold"
        case purple = "purple"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .blue: return "Blue"
            case .monochrome: return "Monochrome"
            case .gold: return "Gold"
            case .purple: return "Purple"
            }
        }

        /// Glow color for subtle effects on UI elements
        public var glowColor: Color {
            Color.white.opacity(0.92)
        }

        /// Border color for timeline control buttons (subtle accent)
        public var controlBorderColor: Color {
            Color.white.opacity(0.28)
        }
    }

    // MARK: - Milestone Definition

    public enum Milestone: Int, CaseIterable {
        case tenHours = 10
        case hundredHours = 100
        case thousandHours = 1000
        case tenThousandHours = 10000

        var hoursThreshold: TimeInterval {
            TimeInterval(rawValue) * 60 * 60  // Convert hours to seconds
        }

        var dismissedKey: String {
            "milestoneCelebration_\(rawValue)h_dismissed"
        }

        var title: String {
            switch self {
            case .tenHours: return "10 Hours!"
            case .hundredHours: return "100 Hours!"
            case .thousandHours: return "1,000 Hours!"
            case .tenThousandHours: return "10,000 HOURS"
            }
        }

        var message: String {
            switch self {
            case .tenHours:
                return """
                You've just hit 10 hours of captured screen time. Retrace is starting to become a real memory layer for your Mac.

                The goal is simple: keep the useful context, skip the stale noise, and make your work searchable when you need it.
                
                Whenever you think "where did I see that?", this is the place to look.
                """

            case .hundredHours:
                return """
                100 hours of screen context captured. This is exactly the kind of long-running memory Retrace Agentfirst is built for.

                It should help you recover decisions, agent work, browser trails, and the small details that usually vanish.

                Keep it local. Keep it useful. Keep building.
                """

            case .thousandHours:
                return """
                ONE THOUSAND HOURS. Retrace has been running beside real work long enough to become infrastructure.

                This is a serious local context archive now: searchable, private, and shaped around your workflow.

                Time to turn that memory into better agents, better recall, and fewer lost threads.
                """

            case .tenThousandHours:
                return """
                TEN THOUSAND HOURS. This Mac has a serious memory now.

                At this point Retrace is not just a recorder. It is a personal archive for decisions, projects, agents, and the trails between them.

                Keep building from the archive.
                """
            }
        }
    }

    // MARK: - Configuration

    /// UserDefaults suite for app settings
    private static let settingsStore = UserDefaults(suiteName: "io.retrace.app") ?? .standard

    /// Key for storing cumulative screen time (survives database resets)
    private static let cumulativeScreenTimeKey = "retraceCumulativeScreenTimeSeconds"

    /// Key for storing the timestamp of the last counted segment
    /// Only segments created AFTER this date will be added to cumulative time
    private static let lastCountedTimestampKey = "retraceLastCountedTimestamp"

    /// Key for storing the user's color theme preference
    private static let colorThemePreferenceKey = "retraceColorThemePreference"

    /// Key for storing debug theme override (shared across instances)
    #if DEBUG
    private static let debugThemeOverrideKey = "retraceDebugThemeOverride"
    #endif

    // MARK: - Static Access

    /// Get the current color theme (respects user's preference)
    /// Marked nonisolated because it only reads from thread-safe UserDefaults
    public nonisolated static func getCurrentTheme() -> ColorTheme {
        let settingsStore = UserDefaults(suiteName: "io.retrace.app") ?? .standard
        #if DEBUG
        if let rawValue = settingsStore.string(forKey: "retraceDebugThemeOverride"),
           let theme = ColorTheme(rawValue: rawValue) {
            return theme
        }
        #endif

        if let rawValue = settingsStore.string(forKey: "retraceColorThemePreference"),
           let theme = ColorTheme(rawValue: rawValue) {
            return theme
        }
        return .monochrome
    }

    /// Get the user's color theme preference
    public nonisolated static func getColorThemePreference() -> ColorTheme {
        let settingsStore = UserDefaults(suiteName: "io.retrace.app") ?? .standard
        if let rawValue = settingsStore.string(forKey: "retraceColorThemePreference"),
           let theme = ColorTheme(rawValue: rawValue) {
            return theme
        }
        return .monochrome
    }

    /// Set the user's color theme preference
    public nonisolated static func setColorThemePreference(_ theme: ColorTheme) {
        let settingsStore = UserDefaults(suiteName: "io.retrace.app") ?? .standard
        settingsStore.set(theme.rawValue, forKey: "retraceColorThemePreference")
        // Post notification so views can update
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .colorThemeDidChange, object: theme)
        }
    }

    #if DEBUG
    /// Set the debug theme override (shared across all views)
    /// Marked nonisolated because it only writes to thread-safe UserDefaults
    public nonisolated static func setDebugThemeOverride(_ theme: ColorTheme?) {
        let settingsStore = UserDefaults(suiteName: "io.retrace.app") ?? .standard
        if let theme = theme {
            settingsStore.set(theme.rawValue, forKey: "retraceDebugThemeOverride")
        } else {
            settingsStore.removeObject(forKey: "retraceDebugThemeOverride")
        }
    }

    /// Get the debug theme override
    public nonisolated static func getDebugThemeOverride() -> ColorTheme? {
        let settingsStore = UserDefaults(suiteName: "io.retrace.app") ?? .standard
        guard let rawValue = settingsStore.string(forKey: "retraceDebugThemeOverride") else {
            return nil
        }
        return ColorTheme(rawValue: rawValue)
    }
    #endif

    // MARK: - Private State

    private let coordinator: AppCoordinator
    private var checkTimer: Timer?

    // MARK: - Initialization

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        startMonitoring()
    }

    // MARK: - Monitoring

    /// Start monitoring for milestones
    private func startMonitoring() {
        // Check immediately on init
        Task {
            await updateCumulativeTime()
            await checkForMilestones()
        }

        // Also check periodically (every 10 minutes)
        checkTimer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateCumulativeTime()
                await self?.checkForMilestones()
            }
        }
    }

    /// Update the cumulative screen time counter
    /// Uses timestamp-based tracking: only counts segments created after the last checkpoint
    private func updateCumulativeTime() async {
        do {
            let lastCountedTimestamp = getLastCountedTimestamp()
            let cumulativeTime = Self.settingsStore.double(forKey: Self.cumulativeScreenTimeKey)
            let liveDatabaseDuration = try await coordinator.getTotalCapturedDuration()

            // Get duration of segments created after the last checkpoint
            let newDuration: TimeInterval
            if let lastTimestamp = lastCountedTimestamp {
                newDuration = try await coordinator.getCapturedDurationAfter(date: lastTimestamp)
            } else {
                // First time - count all existing segments
                newDuration = liveDatabaseDuration
            }

            let updatedCumulative = CumulativeScreenTimeTracker.reconciledCumulativeDuration(
                storedCumulativeDuration: cumulativeTime,
                incrementalDuration: newDuration,
                liveDatabaseDuration: liveDatabaseDuration
            )

            if updatedCumulative > cumulativeTime {
                Self.settingsStore.set(updatedCumulative, forKey: Self.cumulativeScreenTimeKey)
                let reconciledIncrementalDuration = updatedCumulative - cumulativeTime
                Log.debug("[MilestoneCelebrationManager] Synced \(reconciledIncrementalDuration / 3600)h, cumulative: \(updatedCumulative / 3600)h", category: .ui)
            }

            // Update checkpoint to now
            Self.settingsStore.set(Date().timeIntervalSince1970, forKey: Self.lastCountedTimestampKey)

        } catch {
            Log.error("[MilestoneCelebrationManager] Failed to update cumulative time: \(error)", category: .ui)
        }
    }

    /// Get the timestamp of the last counted segment checkpoint
    private func getLastCountedTimestamp() -> Date? {
        guard let timestamp = Self.settingsStore.object(forKey: Self.lastCountedTimestampKey) as? TimeInterval,
              timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Get the total cumulative screen time (persisted across database resets)
    private func getCumulativeScreenTime() -> TimeInterval {
        Self.settingsStore.double(forKey: Self.cumulativeScreenTimeKey)
    }

    /// Get the user's current color theme
    public var currentTheme: ColorTheme {
        Self.getCurrentTheme()
    }

    /// Get cumulative hours for display
    public var cumulativeHours: Int {
        return Int(getCumulativeScreenTime() / 3600)
    }

    /// Check if user has reached any uncelebrated milestones
    /// Only shows the HIGHEST achieved milestone (auto-dismisses lower ones)
    private func checkForMilestones() async {
        // Don't show if already showing a milestone
        guard currentMilestone == nil else { return }

        let totalDuration = getCumulativeScreenTime()

        // Find the highest achieved milestone
        var highestAchieved: Milestone? = nil
        for milestone in Milestone.allCases {
            if totalDuration >= milestone.hoursThreshold {
                highestAchieved = milestone
            }
        }

        // If we found an achieved milestone that hasn't been dismissed, show it
        // Also auto-dismiss all lower milestones so users don't see them sequentially
        if let highest = highestAchieved {
            // Auto-dismiss all milestones below the highest achieved
            for milestone in Milestone.allCases {
                if milestone.rawValue < highest.rawValue && !hasBeenDismissed(milestone) {
                    Self.settingsStore.set(true, forKey: milestone.dismissedKey)
                    Log.debug("[MilestoneCelebrationManager] Auto-dismissed \(milestone.rawValue)h milestone (user already at \(highest.rawValue)h)", category: .ui)
                }
            }

            // Show the highest milestone if not dismissed
            if !hasBeenDismissed(highest) {
                currentMilestone = highest
                Log.info("[MilestoneCelebrationManager] Showing \(highest.rawValue)h milestone - cumulative: \(totalDuration / 3600) hours", category: .ui)
            }
        }
    }

    // MARK: - State Checks

    /// Check if a milestone has been dismissed
    private func hasBeenDismissed(_ milestone: Milestone) -> Bool {
        Self.settingsStore.bool(forKey: milestone.dismissedKey)
    }

    // MARK: - User Actions

    /// Dismiss the current milestone celebration
    public func dismissCurrentMilestone() {
        guard let milestone = currentMilestone else { return }
        Self.settingsStore.set(true, forKey: milestone.dismissedKey)
        currentMilestone = nil
        Log.debug("[MilestoneCelebrationManager] User dismissed \(milestone.rawValue)h milestone", category: .ui)
    }

    /// Open the support link for the current milestone
    public func openSupportLink() {
        guard let milestone = currentMilestone else { return }
        let urlString: String
        switch milestone {
        case .tenHours:
            urlString = "https://github.com/aryateja2106/retrace-agentfirst"
        case .hundredHours:
            urlString = "https://github.com/sponsors/haseab"
        case .thousandHours:
            urlString = "https://github.com/aryateja2106/retrace-agentfirst/issues"
        case .tenThousandHours:
            // No support link for 10k.
            return
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open the Discord community invite link
    public func openDiscordLink() {
        guard let url = URL(string: "https://github.com/aryateja2106/retrace-agentfirst/discussions") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Cleanup

    deinit {
        checkTimer?.invalidate()
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when the color theme preference changes
    static let colorThemeDidChange = Notification.Name("colorThemeDidChange")
}

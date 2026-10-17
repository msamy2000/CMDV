import Foundation
import ServiceManagement

@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let agentLabel = "com.cmdv.app"
    private static let hasConfiguredFirstLaunchKey = "CMDV.hasConfiguredFirstLaunchLogin"

    @Published public private(set) var isEnabled: Bool = false

    private var launchAgentPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(Self.agentLabel).plist")
    }

    public init() {
        refreshStatus()
    }

    /// Ensures Launch at Login is enabled automatically on first startup.
    public func ensureEnabledOnFirstLaunch() {
        if !UserDefaults.standard.bool(forKey: Self.hasConfiguredFirstLaunchKey) {
            setEnabled(true)
            UserDefaults.standard.set(true, forKey: Self.hasConfiguredFirstLaunchKey)
        } else {
            refreshStatus()
        }
    }

    public func refreshStatus() {
        let smEnabled = (SMAppService.mainApp.status == .enabled)
        let plistExists = FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
        self.isEnabled = smEnabled || plistExists
    }

    public func toggle() {
        setEnabled(!isEnabled)
    }

    public func setEnabled(_ enabled: Bool) {
        if enabled {
            // 1. Attempt native SMAppService registration
            try? SMAppService.mainApp.register()
            // 2. Also write LaunchAgent plist so ad-hoc signed /Applications/CMDV.app starts reliably on login
            writeLaunchAgentPlist()
        } else {
            try? SMAppService.mainApp.unregister()
            removeLaunchAgentPlist()
        }
        refreshStatus()
    }

    private func resolveExecutablePath() -> String {
        let installedPath = "/Applications/CMDV.app/Contents/MacOS/CMDV"
        if FileManager.default.isExecutableFile(atPath: installedPath) {
            return installedPath
        }
        return Bundle.main.executablePath ?? installedPath
    }

    private func writeLaunchAgentPlist() {
        let launchAgentsDir = launchAgentPlistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let executablePath = resolveExecutablePath()
        let plistDict: [String: Any] = [
            "Label": Self.agentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]

        if let data = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0) {
            try? data.write(to: launchAgentPlistURL, options: .atomic)
        }
    }

    private func removeLaunchAgentPlist() {
        try? FileManager.default.removeItem(at: launchAgentPlistURL)
    }
}

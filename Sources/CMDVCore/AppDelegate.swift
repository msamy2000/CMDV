import Foundation
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public private(set) var store: HistoryStore!
    public private(set) var monitor: ClipboardMonitor!
    public private(set) var pasteService: PasteService!
    public private(set) var panelController: FloatingPanelController!
    public private(set) var statusBarController: StatusBarController!
    public private(set) var hotKeyManager: HotKeyManager!
    public private(set) var launchAtLoginManager: LaunchAtLoginManager!
    public private(set) var permissionsManager: PermissionsManager!

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure embedded menu bar agent behavior (no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        self.store = HistoryStore()
        self.monitor = ClipboardMonitor(store: store)
        self.pasteService = PasteService(store: store, monitor: monitor)
        self.panelController = FloatingPanelController(store: store, pasteService: pasteService)
        self.launchAtLoginManager = LaunchAtLoginManager()
        self.permissionsManager = PermissionsManager()

        self.statusBarController = StatusBarController(
            store: store,
            panelController: panelController,
            launchAtLoginManager: launchAtLoginManager,
            permissionsManager: permissionsManager
        )

        self.hotKeyManager = HotKeyManager { [weak self] in
            Task { @MainActor [weak self] in
                self?.panelController.toggleAtCursorOrCaret()
            }
        }
        _ = self.hotKeyManager.registerCmdShiftV()

        // Start clipboard polling
        self.monitor.start()

        // Ensure Launch at Login is registered on first startup
        self.launchAtLoginManager.ensureEnabledOnFirstLaunch()

        // Request Accessibility permissions on startup if not yet granted
        self.permissionsManager.checkAndRequestOnStartup()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        hotKeyManager?.unregister()
        store?.saveToDisk()
    }
}

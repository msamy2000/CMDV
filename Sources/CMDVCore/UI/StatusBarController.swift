import Foundation
import AppKit

@MainActor
public final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: HistoryStore
    private let panelController: FloatingPanelController
    private let launchAtLoginManager: LaunchAtLoginManager
    private let permissionsManager: PermissionsManager

    public init(
        store: HistoryStore,
        panelController: FloatingPanelController,
        launchAtLoginManager: LaunchAtLoginManager,
        permissionsManager: PermissionsManager
    ) {
        self.store = store
        self.panelController = panelController
        self.launchAtLoginManager = launchAtLoginManager
        self.permissionsManager = permissionsManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "CMDV Clipboard History") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "📋"
        }
        button.toolTip = "CMDV Clipboard History (⇧⌘V)"
        button.target = self
        button.action = #selector(handleStatusBarClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            panelController.toggleAnchored(toStatusButton: statusItem.button)
            return
        }

        let isRightClick = (event.type == .rightMouseUp)
            || event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.option)

        if isRightClick {
            if panelController.isVisible {
                panelController.closePanel(restoreFocus: false)
            }
            presentContextMenu()
        } else {
            panelController.toggleAnchored(toStatusButton: statusItem.button)
        }
    }

    private func presentContextMenu() {
        store.purgeExpired(now: Date())
        launchAtLoginManager.refreshStatus()
        permissionsManager.refreshStatus()

        let menu = NSMenu(title: "CMDV")

        let headerItem = NSMenuItem(
            title: "CMDV — \(store.items.count) / \(store.maxItems) items (5-day window)",
            action: nil,
            keyEquivalent: ""
        )
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let openItem = NSMenuItem(
            title: "Show Clipboard Cards (⇧⌘V)",
            action: #selector(openCardsFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(
            title: "Clear All History",
            action: #selector(clearHistoryAction),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.isEnabled = !store.items.isEmpty
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "Start with macOS (Launch at Login)",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = launchAtLoginManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        let axGranted = permissionsManager.isAccessibilityGranted
        let permTitle = axGranted
            ? "Accessibility Permission: Granted ✓"
            : "Grant Accessibility Permission…"
        let permItem = NSMenuItem(
            title: permTitle,
            action: #selector(handlePermissionsMenuAction),
            keyEquivalent: ""
        )
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit CMDV",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openCardsFromMenu() {
        panelController.toggleAnchored(toStatusButton: statusItem.button)
    }

    @objc private func clearHistoryAction() {
        store.clearAll()
    }

    @objc private func toggleLaunchAtLogin() {
        launchAtLoginManager.toggle()
    }

    @objc private func handlePermissionsMenuAction() {
        if permissionsManager.refreshStatus() {
            permissionsManager.openAccessibilitySettings()
        } else {
            permissionsManager.requestAccessibilityPermission()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

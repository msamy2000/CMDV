import Foundation
import AppKit
import ApplicationServices
import SwiftUI

@MainActor
public final class PermissionsManager: ObservableObject {
    @Published public private(set) var isAccessibilityGranted: Bool = false

    private var pollTimer: Timer?
    private var onboardingWindow: NSWindow?

    public init() {
        refreshStatus()
    }

    /// Checks whether the current process has Accessibility permission.
    @discardableResult
    public func refreshStatus() -> Bool {
        let trusted = AXIsProcessTrusted()
        if isAccessibilityGranted != trusted {
            isAccessibilityGranted = trusted
        }
        return trusted
    }

    /// Called on app startup: requests Accessibility permission if not yet granted and shows a guided prompt.
    public func checkAndRequestOnStartup() {
        if refreshStatus() {
            return
        }

        // Trigger the macOS system Accessibility prompt dialog
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        showOnboardingWindow()
        startPollingForGrant()
    }

    /// Prompts for Accessibility permission explicitly when requested from the menu bar.
    public func requestAccessibilityPermission() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        openAccessibilitySettings()
        showOnboardingWindow()
        startPollingForGrant()
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPollingForGrant() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.refreshStatus() {
                    self.pollTimer?.invalidate()
                    self.pollTimer = nil
                    self.onboardingWindow?.close()
                    self.onboardingWindow = nil
                }
            }
        }
    }

    public func showOnboardingWindow() {
        if let existing = onboardingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = PermissionsOnboardingView(
            manager: self,
            onDismiss: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CMDV Permissions"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }
}

struct PermissionsOnboardingView: View {
    @ObservedObject var manager: PermissionsManager
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Auto-Paste for CMDV")
                        .font(.headline)
                    Text("Accessibility permission is needed on macOS")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("CMDV uses macOS Accessibility to automatically paste your selected clipboard item when you press Enter or click a card (just like Win+V in Windows 11), and to position the popup at your active text cursor.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Circle()
                    .fill(manager.isAccessibilityGranted ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(manager.isAccessibilityGranted ? "Accessibility Permission Granted" : "Waiting for Accessibility Permission in System Settings…")
                    .font(.caption.weight(.medium))
            }
            .padding(.vertical, 4)

            Spacer()

            HStack {
                Button("Continue in Copy-Only Mode") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Open System Settings…") {
                    manager.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(24)
        .frame(width: 420, height: 270)
    }
}
